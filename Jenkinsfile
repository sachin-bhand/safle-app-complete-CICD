pipeline {
    agent any

    environment {
        REGION    = 'ap-south-1'
        APP_NAME  = "myapp"
        IMAGE_TAG = "${BUILD_NUMBER}"
        TF_DIR    = 'terraform'
    }

    stages {

        stage('Example') {
            steps {
                echo "Region is ${REGION}"
            }
        }

        stage('Checkout Code') {
            steps {
                git branch: 'main',
                url: 'git@github.com:sachin-bhand/safle-app-complete-CICD.git',
                credentialsId: 'github-ssh'
            }
        }

        stage('Configure AWS Credentials') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding',
                credentialsId: 'aws-credentials']]) {
                    sh 'aws sts get-caller-identity'
                }
            }
        }


        stage('Terraform Init') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding',
                credentialsId: 'aws-credentials']]) {
                   dir("${TF_DIR}") {
                      sh 'terraform init'
                }   
            }
        }
    }
        stage('Terraform Destroy Old Infra') {
           steps {
            withCredentials([[$class: 'AmazonWebServicesCredentialsBinding',
            credentialsId: 'aws-credentials']]) {
              dir("${TF_DIR}") {
                sh 'terraform destroy -auto-approve || true'
            }
        }
    }
}

        stage('Terraform Apply Infra') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding',
                credentialsId: 'aws-credentials']]) {
                  dir("${TF_DIR}") {
                      sh 'terraform apply -auto-approve -var="aws_region=${REGION}"'
                }
            }
        }
    }

        stage('Get Terraform Outputs') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding',
                credentialsId: 'aws-credentials']]) {
                   script {
                    env.ECR_URI = sh(
                        script: "cd ${TF_DIR} && terraform output -raw ecr_repo_url -no-color",
                        returnStdout: true
                    ).trim().replaceAll("\\u001B\\[[;\\d]*m", "")

                    env.ECS_CLUSTER = sh(
                        script: "cd ${TF_DIR} && terraform output -raw ecs_cluster_name -no-color",
                        returnStdout: true
                   ).trim().replaceAll("\\u001B\\[[;\\d]*m", "")

                    env.ECS_SERVICE = sh(
                        script: "cd ${TF_DIR} && terraform output -raw ecs_service_name -no-color",
                        returnStdout: true
                    ).trim().replaceAll("\\u001B\\[[;\\d]*m", "")
                echo "ECR URI = ${ECR_URI}"
                   }
            }
        }
        }

        stage('Login to ECR') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding',
                credentialsId: 'aws-credentials']]) {
                sh """
                aws ecr get-login-password --region ${REGION} | \
                docker login --username AWS --password-stdin ${ECR_URI}
                """
            }
        }
    }

        stage('Build Docker Image') {
            steps {
                sh """
                docker build -t ${APP_NAME}:${IMAGE_TAG} .
                docker tag ${APP_NAME}:${IMAGE_TAG} ${ECR_URI}:${IMAGE_TAG}
                """
            }
        }

        stage('Push Docker Image') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding',
                credentialsId: 'aws-credentials']]) {
                sh "docker push ${ECR_URI}:${IMAGE_TAG}"
            }
        }
    }

        stage('Update ECS Service') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding',
                credentialsId: 'aws-credentials']]) {
                sh """
                aws ecs update-service \
                --cluster ${ECS_CLUSTER} \
                --service ${ECS_SERVICE} \
                --force-new-deployment \
                --region ${REGION}
                """
            }
        }
    }

        stage('Verify Deployment') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding',
                credentialsId: 'aws-credentials']]) {
                sh """
                aws ecs describe-services \
                --cluster ${ECS_CLUSTER} \
                --services ${ECS_SERVICE} \
                --region ${REGION}
                """
            }
        }
    }
    }

    post {
        success {
            echo 'All Infrastructure Created + App Deployed Successfully!'
        }

        failure {
            echo 'Pipeline Failed!'
        }
    }
}