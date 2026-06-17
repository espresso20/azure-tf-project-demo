# azure-tf-project-demo

Minimal-cost Azure demo stack — resource group, virtual network, one subnet, an
SSH-scoped NSG, and (optionally) a single small Linux VM with a public IP. Built
on the same scaffold as our AWS Terraform stacks (`aws-stack-tf-default-template`):
same Makefile-driven workflow and env-split tfvars; the state backend and auth are
the Azure-specific bits.

The shape follows the minimal-network spec — a single light VM that needs internet
access — tuned for the cheapest functional footprint: B-series burstable VM,
Standard HDD OS disk, no NAT Gateway / Firewall / Load Balancer / Bastion.

## Structure

```
.
├── Makefile                          # bootstrap / init / plan / apply / destroy / validate / fmt
├── scripts/
│   └── bootstrap-state.sh            # one-time Azure Storage state backend creation
└── terraform/
    ├── providers.tf                  # azurerm provider + backend "azurerm" {}
    ├── variables.tf                  # typed stack variables
    ├── main.tf                       # resource group + vnet + subnet + nsg + (optional) pip/nic/vm
    ├── outputs.tf                    # rg name, vnet/subnet ids, public ip, ssh command
    └── env/
        └── dev/
            ├── dev.backend.tfvars    # tf backend state variables
            └── dev.terraform.tfvars  # tf stack variables — fill these in
```

## Quick start

```bash
az login
# edit terraform/env/dev/dev.terraform.tfvars:
#   - subscription_id, org_id
#   - allowed_ssh_cidr  (your IP, e.g. 203.0.113.4/32)
#   - admin_ssh_public_key  (contents of ~/.ssh/id_ed25519.pub)
# and set a real subscription_id in dev.backend.tfvars
make bootstrap dev   # one-time: creates the RG + storage account + blob container
make init dev
make plan dev
make apply dev
```

`terraform output ssh_command` prints the line to connect once the VM is up.

## What you get (and what it costs)

| Resource                     | Notes                                          | Cost                |
| ---------------------------- | ---------------------------------------------- | ------------------- |
| Resource group               | Created by the stack                           | Free                |
| Virtual network + subnet     | Single /24 VNet, one /26 subnet                | Free                |
| Network security group       | Inbound SSH only, scoped to allowed_ssh_cidr   | Free                |
| Public IP (Standard, Static) | Required for inbound; Basic SKU is retired     | ~a few $/mo         |
| Linux VM (B1s) + OS disk     | Burstable + Standard HDD; deallocate when idle | ~$6–15/mo light use |

Set `create_vm = false` for a network-only stack (just VNet + subnet + NSG, all free).

**Deviations from the generic minimal-cost advice**, because some of it is dated:

- **Public IP is Standard/Static, not Basic/dynamic.** Basic SKU public IPs were
  retired by Azure (Sep 2025). Standard Static is the floor now.
- **SSH is not meant to be open to the world.** Set `allowed_ssh_cidr` to your own
  `/32`. The `"*"` default works but is a liability for anything long-lived.
- Password auth is disabled — `admin_ssh_public_key` is required when `create_vm = true`
  (a plan-time precondition enforces it so you don't deploy an unreachable box).

To trim further: use Spot (not wired in — add `priority`/`eviction_policy` if needed),
deallocate the VM when idle (`az vm deallocate`), and keep egress low.

## Tagging

Unlike the AWS template's provider-level `default_tags`, azurerm has no such feature,
so cross-cutting tags live in `local.common_tags` (sourced from `var.tags`, with
`org_id` folded in as `OrgId`) and are merged onto each taggable resource. Subnets
don't carry tags in azurerm.

## Makefile reference

```
make bootstrap dev
make init      dev
make plan      dev
make plan      dev  target='azurerm_linux_virtual_machine.this'
make apply     dev
make apply     dev  auto=true
make destroy   dev  auto=true
make fmt
```

Environments: `dev` | `staging` | `prod`
Add an env by creating `terraform/env/<env>/<env>.backend.tfvars` and
`terraform/env/<env>/<env>.terraform.tfvars`.
