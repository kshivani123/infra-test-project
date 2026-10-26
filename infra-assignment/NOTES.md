# Notes

Layout:

```
task1-ec2/               module + root config (backend.tf is the task 2 change)
task2-state-backend/     S3 bucket + DynamoDB lock table (bootstrap, local state)
task3-iam/account-a/     groups, users, roleA, roleB
task3-iam/account-b/     bucket + roleC
task4-ci-policy/         ci-policy.json + attachment to the ci user
task5-bugfix/            fixed snippet
```

Apply order matters for task 3: account-a first, then account-b. IAM checks
that a principal in a trust policy actually exists, so roleC can't be created
before roleB.

Region is ap-south-1 everywhere, account IDs are the ones from the brief.

---

## Task 1 - EC2

All five instances come from `var.instances` (a map keyed by instance name).
The key is the Name tag and the key in both output maps.

| name       | type      | root volume              | key pair    |
|------------|-----------|--------------------------|-------------|
| bastion-01 | t3.micro  | standard (magnetic), 8G  | stg-bastion |
| web-01     | t3.small  | gp2, 20G                 | stg-web     |
| app-01     | m5.large  | gp3, 30G                 | stg-app     |
| batch-01   | c5.xlarge | io1, 50G / 2000 IOPS     | stg-batch   |
| db-01      | r5.large  | io2, 100G / 5000 IOPS    | stg-db      |

Getting five *different* root volume types was a bit forced: only gp2, gp3,
io1, io2 and standard can be boot volumes (st1/sc1 can't), so that's exactly
all of them. I wouldn't put magnetic on anything real - it's there to satisfy
the requirement. There's a validation on the variable that rejects st1/sc1 and
io1/io2 without IOPS, so you find out at plan time instead of from the EC2 API.

### Which instance is protected, and why

**db-01.** It's the only stateful box in the set - the data lives on its
volume, and it's the one where "terraform replaced it" means an outage plus a
restore, not just a new instance coming up. Bastion, web, app and batch can all
be rebuilt from the AMI + config with no loss. It's also the most expensive
volume (io2, provisioned IOPS) so recreating it isn't free either.

How it's done is worth calling out, because the obvious approach doesn't work:
`prevent_destroy` has to be a literal. You can't write
`prevent_destroy = each.value.protected` - Terraform errors on it. So the
module splits the input map in two and has one resource block for normal
instances and one for protected ones (with `prevent_destroy = true`). Still a
single input variable, just two `for_each` resources reading from it.

Things I added on top, since `prevent_destroy` on its own is weaker than it
sounds:

- It only blocks Terraform. Someone in the console can still terminate the
  instance, so the protected one also has `disable_api_termination = true`.
- If someone deletes the entry from the tfvars (or the whole resource block),
  the lifecycle setting goes with it and Terraform will happily destroy it.
  Termination protection covers that case too - the API call fails.
- `delete_on_termination = false` on its root volume, so even a deliberate
  termination leaves the data behind.
- Flipping `protected` on an existing instance moves it between resource
  addresses (`aws_instance.this["x"]` -> `aws_instance.protected["x"]`).
  That needs a `moved {}` block or `terraform state mv`, otherwise Terraform
  plans a destroy/create.

Other small choices: `ignore_changes = [ami]` because the AMI comes from the
AL2023 SSM parameter, which changes every release - without it every plan
after an AWS release wants to replace all five instances. IMDSv2 is enforced
and root volumes are encrypted.

---

## Task 2 - Remote state & locking

**What happens today with local state.** The state file is
`terraform.tfstate` on whoever ran apply's laptop. If two people run apply at
the same time:

- Usually they're on different machines, so they have *different* state
  files. Neither knows what the other has created. Person A creates the five
  instances; person B's state says nothing exists, so B creates five more.
  Now there are ten instances, each state file tracks only half, and any later
  destroy/plan from either side is wrong. Same thing in slower motion even
  without simultaneous runs - whoever didn't apply last has stale state.
- If they're on the same box (shared jump host), Terraform does take a local
  lock file, so the second run errors. But that's the only case it covers,
  and the state is still one `rm` or disk failure away from gone, with no
  history.

**What the backend change does.** State moves to one S3 object
(`ec2-fleet/staging/terraform.tfstate`) that everyone reads, so there's a
single source of truth. Before any operation that could write state (plan,
apply, destroy), Terraform puts an item in the `terraform-locks` DynamoDB
table using a conditional write keyed on the state path. If the item is
already there, the second person's run fails immediately with the lock ID,
who holds it and since when - instead of both applying. The lock is removed
when the run finishes. If a run crashes and leaves a stale lock,
`terraform force-unlock <id>` clears it (after checking nobody's actually
running).

Extras in the bootstrap stack: versioning on the bucket (roll back a bad
state), KMS encryption and TLS-only bucket policy (state contains secrets -
e.g. the task 3 access keys), public access blocked, deletion protection on
the table.

Side note: newer Terraform (1.10+) can lock with S3 itself (`use_lockfile =
true`) and the DynamoDB option is deprecated. I used DynamoDB because the task
asks for it; on a fresh setup I'd use the S3 lockfile and skip the table.

---

## Task 3 - IAM

Decisions/assumptions:

- **group1** users (engine, ci) get access keys and no login profile, so there
  is no way for them to use the console. The group itself only lets them
  rotate their own keys; actual permissions are per-user (ci -> task 4
  policy, engine -> can assume roleB).
- **group2** - I read "full console + CLI" as *both access channels*, not
  "AdministratorAccess". The two users (rahul.verma, neha.joshi) get a console
  password (reset on first login) and can create their own access keys. Until
  they enrol MFA they can do nothing except set it up. To actually work they
  assume roleA with MFA. If the intent was admin directly on the group, it's a
  one-line policy attachment, but I'd push back on it.
- **roleA** uses `Allow` + `NotAction: iam:*` rather than AdministratorAccess
  + `Deny iam:*`. A deny on all IAM also blocks `iam:PassRole`, which breaks
  launching anything that runs with a role (EC2 profiles, Lambda, ECS). So I
  allow back PassRole, Get/ListRoles, ListInstanceProfiles and
  CreateServiceLinkedRole. None of those can create or modify identities or
  policies. (Caveat: PassRole on `*` means roleA could pass an existing,
  more-privileged role to an EC2 instance. If that's a concern, scope
  PassRole to a role path like `role/app/*`.)
- **roleB** - only `sts:AssumeRole` on roleC's ARN. Trusted by the `engine`
  user, since that's the workload that needs the bucket in B.
- **roleC** - `s3:*` on one bucket and its objects, trusted by roleB's exact
  ARN.
- Generated secrets (access keys, console passwords) are PGP-encrypted via
  `pgp_key` so they aren't in state/outputs in plain text.

### Q1. Would I give engine and ci IAM users with access keys in production?

No. Long-lived access keys are the thing most likely to leak (CI logs,
someone's `.env`, a public repo) and they work from anywhere until someone
notices and rotates them, which in practice is rarely.

What I'd do instead:

- **ci** - OIDC federation. GitHub Actions / GitLab / Bitbucket can all get a
  token that AWS trusts directly. Create an IAM role whose trust policy
  allows `sts:AssumeRoleWithWebIdentity` from the provider, conditioned on the
  `sub` claim (e.g. `repo:acme/payments-api:ref:refs/heads/main`). The pipeline
  gets credentials that last an hour and only for that repo/branch. Nothing to
  store, nothing to rotate. Same task 4 policy, attached to the role.
- **engine** - depends where it runs. On EC2 -> instance profile. ECS -> task
  role. EKS -> IRSA / Pod Identity. Outside AWS -> IAM Roles Anywhere with a
  cert from our own CA. In every case the SDK picks up temporary creds
  automatically.
- **humans (group2)** - IAM Identity Center (SSO) tied to the company IdP
  instead of IAM users, so offboarding is one switch in the IdP and the CLI
  uses `aws sso login`.

If I were stuck with IAM users (some old on-prem system, say): keys rotated on
a schedule, an `aws:SourceIp` / `aws:SourceVpce` condition so the keys only
work from known networks, and alerting on key usage from anywhere else.

### Q2. roleC trust: Account A root vs roleB's ARN

Trusting `arn:aws:iam::000000000000:root` doesn't mean "only the root user".
It means "I trust account A to decide" - any principal in A whose own
policies allow `sts:AssumeRole` on roleC can assume it. Account B gives away
control over who gets into its bucket.

Concretely with this setup: roleA is "admin except IAM". `sts:AssumeRole` is
not an IAM action, it's STS, so roleA's `NotAction: iam:*` allows it on any
resource. If roleC trusted A's root, anyone holding roleA - or anyone who can
attach a policy to anything in A - could get into account B's bucket. With
roleB's specific ARN in the trust policy, account B only accepts that one
role; nothing account A does with its own policies changes that. That's what
the brief means by "not by anything else in Account A".

One more detail: when the trust policy names a role ARN, IAM stores it as the
role's unique ID (AROA...). If roleB is deleted and recreated with the same
name, the trust doesn't automatically carry over - it shows the old ID and
needs updating. That's annoying operationally, but it's on purpose: it stops
someone from deleting a role and recreating it with the same name to inherit
its access. (If you need it to survive recreation, the alternative is trust
the root + a `aws:PrincipalArn` condition on roleB's ARN.)

---

## Task 4 - ci policy

`task4-ci-policy/ci-policy.json`. Names used: ECR repo `payments-api`, ECS
cluster `prod-cluster`, service `payments-api`, artifact bucket
`acme-build-artifacts`.

What's in it and why:

- `ecr:GetAuthorizationToken` on `*` - that action has no resource-level
  support, it's required for `docker login`.
- Layer upload + `PutImage` on the one repo. `BatchGetImage` is included
  because docker/buildx check the existing manifest during push (and for
  `--cache-from`); it's read-only on the same repo.
- `ecs:RegisterTaskDefinition` / `DescribeTaskDefinition` on `*` - neither
  can be scoped to a family, AWS doesn't support it. Describe is there because
  most deploy tooling fetches the current task def and swaps the image.
- `ecs:UpdateService` / `DescribeServices` only on the one service ARN.
  Describe is what `aws ecs wait services-stable` polls.
- `iam:PassRole` only on the service's execution role and task role, and only
  when passed to `ecs-tasks.amazonaws.com`. Registering a task definition
  that references a role requires PassRole, and this is the statement that
  actually limits blast radius: since RegisterTaskDefinition can't be scoped,
  this is what stops CI from registering a task that runs as some admin role.
- `s3:ListBucket` on the bucket, `s3:GetObject` on its objects. Nothing else.

Deliberately left out:

- **Any write/delete on ECR beyond pushing**: `BatchDeleteImage`,
  `DeleteRepository`, `CreateRepository`, `SetRepositoryPolicy`,
  `PutLifecyclePolicy`, `PutImageTagMutability`. Repo setup is
  infrastructure, done in Terraform, not by the pipeline. A compromised
  pipeline shouldn't be able to wipe images or open the repo up.
- **`ecs:CreateService`, `DeleteService`, `RunTask`, `DeregisterTaskDefinition`,
  `ListClusters` etc.** - CI rolls an existing service, it doesn't create
  services or run one-off tasks (RunTask would let it run arbitrary commands
  with the task role). Old task def revisions can be cleaned up separately.
- **`iam:PassRole` on `*`** - the most common mistake in these policies. With
  wildcard PassRole + RegisterTaskDefinition, CI could run a container as any
  role in the account, which is effectively admin.
- **`s3:PutObject` / `DeleteObject` / `GetBucketPolicy`** etc. - read only,
  as asked. Also no `s3:ListAllMyBuckets`; the pipeline knows its bucket name.
- **CloudWatch Logs** - not needed to deploy. The task execution role writes
  the logs, not CI.

Things I'd mention but didn't add without knowing the setup: if the artifact
bucket uses SSE-KMS, CI also needs `kms:Decrypt` on that key; if the ECR repo
uses a customer KMS key, `kms:GenerateDataKey`/`Decrypt` on it. And ideally
this policy goes on an OIDC role (see Q1), not the user.

---

## Task 5 - the bug

Three problems; the first is the one that actually stops the cross-account
assume from ever working.

1. **Wrong principal type.** The trust policy names
   `arn:aws:iam::000000000000:user/roleB`. roleB is a role, so its ARN is
   `arn:aws:iam::000000000000:role/roleB`. There's no *user* called roleB, so
   when Terraform calls CreateRole, IAM rejects the trust policy with
   `MalformedPolicyDocument: Invalid principal in policy` - IAM validates that
   principals exist. This doesn't show up in `terraform plan`, only at apply,
   which is why it's easy to miss. (And if a user named roleB *did* exist, it
   would be worse: the role would be created and trust the wrong identity,
   while the real roleB would get AccessDenied on AssumeRole.)

2. **`role = [aws_iam_role.roleC.id](http://aws_iam_role.rolec.id/)`** isn't
   valid HCL - it's a markdown link that got pasted in (looks like something
   auto-linked `aws_iam_role.roleC.id` because it resembles a domain). Terraform
   won't even parse the file, so in practice this is the first error you'd
   hit. Fixed to `aws_iam_role.roleC.name`. (`.id` would also work - for
   aws_iam_role the id is the name - but `.name` says what it means.)

3. **`s3:*` on `Resource = "*"`.** Not a failure, but it's full S3 on every
   bucket in account B, and the requirement is one named bucket. Scoped to
   the bucket ARN (for bucket-level actions like ListBucket) and
   `bucket/*` (for object actions) - you need both, since S3 actions apply to
   one or the other.

Also worth noting, since the snippet only shows account B's side: a
cross-account assume needs both sides to allow it. roleC's trust policy
lets roleB in, *and* roleB's own permissions must allow `sts:AssumeRole` on
roleC's ARN. If either is missing you get AccessDenied. The fixed version
assumes the account-B provider and pairs with roleB in
`task3-iam/account-a/roles.tf`.
