terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.48"
    }
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.40"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "hcloud" {
  # hcloud validates the shape of its token when the provider is configured, even
  # when no hcloud resources exist in the plan. Without a placeholder, someone
  # building on AWS could not run a plan at all. This is not a credential, it is a
  # 64 character stand-in that satisfies the shape check and nothing else.
  token = var.hcloud_token != "" ? var.hcloud_token : "0000000000000000000000000000000000000000000000000000000000000000"
}

provider "digitalocean" {
  token = var.do_token
}
