##############################################################################
# This file creates custom image using F5-BIGIP qcow2 image hosted in vnfsvc COS
#  - Creates IAM Authorization Policy in vnfsvc account
#  - Creates Custom Image in User account
#
# Note: There are following gaps in ibm is provider and thus using Terraform tricks
# to overcome the gaps for the PoC sake.
# Gap1: IBM IS Provider missing resource implementation for is_image (Create, update, delete)
# Gap2: IBM IS provider missing data source to read logged user provider session info
# example: account-id
##############################################################################

# =============================================================================
# Hack: parse out the user account from the vpc resource crn
# Fix: Get data_source_ibm_iam_target added that would provide information
# about user from provider session
# =============================================================================
locals {
  user_acct_id = "${substr(element(split("a/", data.ibm_is_vpc.f5_vpc.resource_crn), 1), 0, 32)}"
}

##############################################################################
# Create IAM Authorization Policy for user to able to create custom image
# pointing to COS object url hosted in vnfsvc account.
##############################################################################
#resource "ibm_iam_authorization_policy" "authorize_image" {
#  depends_on                  = ["data.ibm_is_vpc.f5_vpc"]
#  provider                    = "ibm.vfnsvc"
#  source_service_account      = "${local.user_acct_id}"
#  source_service_name         = "is"
#  source_resource_type        = "image"
#  target_service_name         = "cloud-object-storage"
#  target_resource_type        = "bucket"
#  roles                       = ["Reader"]
#  target_resource_instance_id = "${var.vnf_f5bigip_cos_instance_id}"
#}

# IAM Authorization to create custom images
data "external" "authorize_policy_for_image" {
  depends_on = ["data.ibm_is_vpc.f5_vpc"]
  program    = ["bash", "${path.module}/scripts/create_auth.sh"]

  query = {
    ibmcloud_endpoint           = "${var.ibmcloud_endpoint}"
    ibmcloud_vnf_svc_api_key    = "${var.ibmcloud_vnf_svc_api_key}"
    source_service_account      = "${local.user_acct_id}"
    source_service_name         = "is"
    source_resource_type        = "image"
    target_service_name         = "cloud-object-storage"
    target_resource_type        = "bucket"
    roles                       = "Reader"
    target_resource_instance_id = "${var.vnf_f5bigip_cos_instance_id}"
    region                      = "${data.ibm_is_region.region.name}"
    resource_group_id           = "${data.ibm_resource_group.rg.id}"
  }
}

resource "ibm_is_image" "f5_custom_image" {
  count            = "${var.copy_f5_image == "y" ? 1 : 0}"
  depends_on       = ["data.external.authorize_policy_for_image"]
  href             = "${var.vnf_f5bigip_cos_image_url}"
  name             = "${var.f5_image_name}"
  operating_system = "centos-7-amd64"

  timeouts {
    create = "30m"
    delete = "10m"
  }
}

data "external" "delete_auth_policy_for_image" {
  depends_on = ["ibm_is_image.f5_custom_image"]
  program    = ["bash", "${path.module}/scripts/delete_auth.sh"]

  query = {
    id                       = "${lookup(data.external.authorize_policy_for_image.result, "id")}"
    ibmcloud_endpoint        = "${var.ibmcloud_endpoint}"
    ibmcloud_vnf_svc_api_key = "${var.ibmcloud_vnf_svc_api_key}"
    region                   = "${data.ibm_is_region.region.name}"
  }
}

data "ibm_is_image" "f5_custom_image" {
  name       = "${var.f5_image_name}"
  depends_on = ["ibm_is_image.f5_custom_image"]
}

output "auth_policy_id" {
  value = "${lookup(data.external.authorize_policy_for_image.result, "id")}"
}
