.PHONY: init plan apply destroy fmt validate clean

init:
	terraform init

plan:
	terraform plan -out=tfplan

apply:
	terraform apply tfplan

destroy:
	terraform destroy -auto-approve
	@echo "Resources destroyed. Check the AWS console to confirm."

fmt:
	terraform fmt -recursive

validate:
	terraform validate

clean:
	rm -rf .terraform .terraform.lock.hcl tfplan terraform.tfstate*
