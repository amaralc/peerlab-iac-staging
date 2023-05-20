# terraform {
#   backend "gcs" {
#     bucket = "peerlab-terraform-state"
#     prefix = "terraform/state"
#     # Filename relative to terraform folder
#     credentials = "credentials.json"
#   }
# }

# # Configure the Fly provider
# provider "fly" {
#   useinternaltunnel    = true
#   internaltunnelorg    = "personal"
#   internaltunnelregion = "gru"
#   fly_api_token        = var.fly_api_token
# }


# locals {
#   commit_hash_file = "${path.module}/.commit_hash"
# }

# resource "null_resource" "get_commit_hash" {
#   provisioner "local-exec" {
#     command = "git rev-parse --short HEAD > ${local.commit_hash_file}" // TODO: Use full commit hash?
#   }
# }

# data "local_file" "commit_hash" {
#   filename   = local.commit_hash_file
#   depends_on = [null_resource.get_commit_hash]
# }

# locals {
#   app_name  = "micro-applications-template-rest-api"
#   image_tag = trimspace(data.local_file.commit_hash.content)
# }

# # Create a Fly.io application
# resource "fly_app" "micro_app_rest_api" {
#   # Create the fly app named "micro-applications-template-rest-api"
#   name = local.app_name
#   org  = "personal"
# }

# # Configure app secrets
# resource "null_resource" "set_fly_secrets" {
#   provisioner "local-exec" {
#     command = <<EOF
#       echo "Commit hash:"
#       echo ${local.commit_hash_file}
#       echo "Settings fly secrets..."
#       cd ../service-rest-api/
#       fly secrets set DATABASE_URL=${var.database_url}
#       fly secrets set DIRECT_URL=${var.direct_url}
#     EOF
#   }
#   depends_on = [fly_app.micro_app_rest_api]
# }

# # Configure ip v4 address
# resource "fly_ip" "ip_v4" {
#   app        = local.app_name
#   type       = "v4"
#   depends_on = [fly_app.micro_app_rest_api]
# }

# # Configure ip v6 addressapp_name
# resource "fly_ip" "ip_v6" {
#   app        = local.app_name
#   type       = "v6"
#   depends_on = [fly_app.micro_app_rest_api]
# }

# # Build image from Dockerfile
# resource "null_resource" "build_and_push_docker_image" {
#   triggers = {
#     dockerfile_content = filesha256("${path.module}/../service-rest-api/Dockerfile")
#   }

#   provisioner "local-exec" {
#     command = <<EOF
#       cd ../../ &&
#       flyctl auth docker &&
#       docker build -t registry.fly.io/${local.app_name}:${local.image_tag} -f apps/service-rest-api/Dockerfile . &&
#       docker push registry.fly.io/${local.app_name}:${local.image_tag}
#     EOF
#   }
# }

# # Update machine metadata to use fly platform v2
# resource "null_resource" "update_unmanaged_machines" {
#   triggers = {
#     image_tag = local.image_tag
#   }

#   provisioner "local-exec" {
#     command = <<EOF
#       for machine_id in $(fly machine list --json | jq -r '.[] | select(.metadata.fly_platform_version != "v2") | .id'); do
#         fly machine update --metadata fly_platform_version=v2 $machine_id
#       done
#     EOF
#   }
# }

# # Create and run machine with that image
# resource "fly_machine" "micro_app_machine_01" {
#   // Regions where the app will be deployed
#   for_each = toset(
#     [
#       "gru", // Sao Paulo
#       "gig"  // Rio de Janeiro
#     ]
#   )
#   app    = local.app_name
#   region = each.value
#   name   = "${local.app_name}-${each.value}"
#   image  = "registry.fly.io/${local.app_name}:${local.image_tag}"
#   # env = {
#   #   DATABASE_PROVIDER = "value"
#   # }
#   services = [
#     {
#       ports = [
#         {
#           port     = 443
#           handlers = ["tls", "http"]
#         },
#         {
#           port     = 80
#           handlers = ["http"]
#         }
#       ]
#       "protocol" : "tcp",
#       "internal_port" : 8080
#     },
#   ]
#   cpus       = 1
#   memorymb   = 256
#   depends_on = [fly_app.micro_app_rest_api, null_resource.build_and_push_docker_image, null_resource.update_unmanaged_machines]
# }



# This block sets up what backend should be used for Terraform. In this case, we are using Google Cloud Storage.
terraform {
  backend "gcs" {
    bucket      = "peerlab-tf-state"
    prefix      = "terraform/state/environments/staging"
    credentials = "credentials.json" # The path to the JSON key file for the Service Account Terraform will use to manage its state
  }
}

# Configure the Google Cloud Provider for Terraform
provider "google" {
  credentials = file(var.credentials_path) # The service account key
  project     = var.project_id             # Your Google Cloud project ID
  region      = var.region                 # The region where resources will be created
}

# The google-beta provider is used for features not yet available in the google provider
provider "google-beta" {
  credentials = file(var.credentials_path) # The service account key
  project     = var.project_id             # Your Google Cloud project ID
  region      = var.region                 # The region where resources will be created
}

# Define local variables
locals {
  service_folder_path = "apps/researchers/peers/svc-rest-api" # The path to the Dockerfile from the root of the repository
  app_name            = "researchers-peers-svc-rest-api"      # The name of the application
}

resource "google_service_account" "researchers-peers-svc" {
  account_id   = local.app_name
  display_name = "Service admin account"
  project      = var.project_id
}

resource "google_project_iam_member" "service_account_user" {
  project = var.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.researchers-peers-svc.email}"
}

# Assign the service account the Cloud Run Admin role
resource "google_project_iam_member" "run_admin" {
  project = var.project_id
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.researchers-peers-svc.email}"
}

# Assign the service account the Cloud Run Invoker role
resource "google_project_iam_member" "run_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.researchers-peers-svc.email}"
}

# Assign the service account the Cloud Build Editor role
resource "google_project_iam_member" "cloudbuild_editor" {
  project = var.project_id
  role    = "roles/cloudbuild.builds.editor"
  member  = "serviceAccount:${google_service_account.researchers-peers-svc.email}"
}

# Create the Service Account Key
resource "google_service_account_key" "researchers-peers-svc-key" {
  service_account_id = google_service_account.researchers-peers-svc.name
}

# Create the secret in Secret Manager
resource "google_secret_manager_secret" "researchers-peers-svc-secret" {
  secret_id = "researchers-peers-svc-secret"
  project   = var.project_id

  replication {
    automatic = true
  }
}

# Add the service account key as a secret version
resource "google_secret_manager_secret_version" "researchers-peers-svc-secret-v1" {
  secret      = google_secret_manager_secret.researchers-peers-svc-secret.id
  secret_data = base64encode(google_service_account_key.researchers-peers-svc-key.private_key)
}

# Fetch the service account key from Google Secret Manager
data "google_secret_manager_secret_version" "researchers-peers-svc_access_secret" {
  # The project in which the secret was created
  project = var.project_id

  # The secret_id corresponds to the name of the secret you created in Secret Manager
  secret = google_secret_manager_secret.researchers-peers-svc-secret.secret_id

  # The version of the secret to fetch. "latest" would fetch the latest version of the secret
  version = "latest"

  # Waits for the secret to be available
  depends_on = [google_secret_manager_secret_version.researchers-peers-svc-secret-v1]
}

# This block defines a Google Cloud Build trigger.
resource "google_cloudbuild_trigger" "default" {
  name     = "push-on-branch-staging" # Name of the trigger
  project  = var.project_id           # The project ID where the trigger will be created
  disabled = false                    # Whether the trigger is active or not

  github {
    owner = var.repo_owner # The GitHub owner's username
    name  = var.repo_name  # The name of the source repository

    push {
      branch = "^feature/DIS-522-move-to-gcp$" # This is a regex pattern for the branch name to trigger on. For example, to trigger only on pushes to the main branch, set this to "^main$".
    }
  }

  # Instead of referencing the Dockerfile, you reference the cloudbuild.yaml file
  filename = "${local.service_folder_path}/cloudbuild.yaml"

  # Substitution variables to be replaced within the build config file. _COMMIT_SHA is a built-in substitution variable.
  substitutions = {
    _COMMIT_SHA = "$COMMIT_SHA"  # This is the commit SHA that triggered the build
    _APP_NAME   = local.app_name # This is the name of the application
  }
}

# # This block defines a Google Cloud Run service. This service will host the Docker image created by the Google Cloud Build trigger.
# resource "google_cloud_run_service" "default" {
#   name     = local.app_name # Name of the service
#   location = var.region     # The region where the service will be located
#   template {
#     spec {
#       # The service account to be used by the service
#       service_account_name = google_service_account.researchers-peers-svc.email

#       # The Docker image to use for the service
#       containers {
#         image = "gcr.io/${google_cloudbuild_trigger.default.project}/${local.app_name}:${google_cloudbuild_trigger.default.substitutions._COMMIT_SHA}"
#       }
#     }
#   }
#   traffic {
#     percent         = 100  # The percent of traffic this version of the service should receive
#     latest_revision = true # Whether traffic should be directed to the latest revision
#   }
# }

# # This block defines a Cloud Run IAM member. This sets the permissions for who can access the Cloud Run service.
# resource "google_cloud_run_service_iam_member" "public" {
#   service  = google_cloud_run_service.default.name     # The name of the service to which the IAM policy will be applied
#   location = google_cloud_run_service.default.location # The location of the service to which the IAM policy will be applied
#   role     = "roles/run.invoker"                       # The role to be granted
#   member   = "allUsers"                                # The user, group, or service account who will have the role granted. In this case, all users.
# }