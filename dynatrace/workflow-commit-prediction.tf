resource "dynatrace_generic_setting" "github_credentials" {
  schema = "app:dynatrace.github.connector:connection"
  scope  = "environment"
  value = jsonencode({
    name  = "Default Connection [${var.demo_name}]"
    type  = "pat"
    token = var.github_token
  })
}

resource "dynatrace_automation_workflow" "commit_prediction" {
  title       = "Commit Davis Prediction [${var.demo_name}]"
  description = "Reacts to events containing suggestions based on Davis resource usage prediction and applies them by creating a pull request on GitHub"
  tasks {
    task {
      name        = "find_manifest"
      description = "Searches for the workload manifest on GitHub"
      action      = "dynatrace.automations:run-javascript"
      active      = true
      input = jsonencode({
        script = chomp(
          <<-EOT

          import {execution} from '@dynatrace-sdk/automation-utils';

               import {credentialVaultClient} from
               "@dynatrace-sdk/client-classic-environment-v2";


               export default async function ({execution_id}) {
                 const ex = await execution(execution_id);
                 const event = ex.params.event;

                 const apiToken = await credentialVaultClient.getCredentialsDetails({
                   id: "${dynatrace_credentials.github_pat.id}",
                 }).then((credentials) => credentials.token);

                 // Search for file
                 const url = 'https://api.github.com/search/code?q=' +
                   `"${var.annotation_prefix}/uuid:%20'$&{event['kubernetes.predictivescaling.target.uuid']}'"` +
                   `+repo:$&{event['kubernetes.predictivescaling.target.repository']}` +
                   `+language:YAML`
               /*
                 const response = await fetch(url, {
                   method: 'GET',
                   headers: {
                     'Authorization': `Bearer $${apiToken}`
                   }
                 }).then(response => response.json());

                const searchResult = response.items[0];


                 // Get default branch
                 const repository = await fetch(searchResult.repository.url, {
                   method: 'GET',
                   headers: {
                     'Authorization': `Bearer $${apiToken}`
                   }
                 }).then(response => response.json());
               */
                 const filepath= getFilePath(event['kubernetes.predictivescaling.target.uuid'])
                 let split= event['kubernetes.predictivescaling.target.repository'].split("/")
                 const repo = split[1];
                 const owner = split[0];
                 const branch= "main"

                 return {
                   owner: owner,
                   repository: repo,
                   filePath: filepath,
                   defaultBranch: branch
                 }
               }


               const getFilePath = (id) => {

                 switch (id)
                 {
                     case "23df7c56-989e-4931-b8a0-b8c9c3090c47":
                       return "apps/otel-demo/hpa-accounting.yaml"
                       break;
                     case "6e1a79ee-67ae-43d9-85f9-f86e9f64cb2f":
                       return "apps/otel-demo/hpa-adservice.yaml"
                       break;
                     case "22940164-667f-4c4f-a83e-2862a5a6903d":
                        return "apps/otel-demo/hpa-cartservice.yaml"
                       break;
                     case "df8dd511-0107-4fc6-a4b4-05a5cbe2da96":
                        return "apps/otel-demo/hpa-checkout.yaml"
                       break;
                     case "99eda3ff-8520-43e8-a5e2-4c7bcf182ff8":
                        return "apps/otel-demo/hpa-currency.yaml"
                       break;
                     case "9eadd65d-0577-4f27-ac3d-ff447c13fe4c":
                        return "apps/otel-demo/hpa-email.yaml"
                        break;
                     case "5877bf0c-beed-4036-bab8-219f74958211":
                        return "apps/otel-demo/hpa-frontend.yaml"
                        break;
                    case "167b9444-08ad-4d22-953e-479131962228":
                        return "apps/otel-demo/hpa-paymentservice.yaml"
                        break;
                     case "e9bf678b-65d8-4da6-9f69-8834f651d84a":
                        return "apps/otel-demo/hpa-productcatalog.yaml"
                        break;
                     case "8a94171b-cf03-4ed3-9d18-fb2e260a80db":
                        return "apps/otel-demo/hpa-quote.yaml"
                        break;
                     case "a94b3775-fc2c-4938-915c-138ec2e7a34a":
                        return "apps/otel-demo/hpa-recommendation.yaml"
                        break;
                     case "fcdf15d5-8d4a-4966-835a-5ca2ea6454f5":
                        return "apps/otel-demo/hpa-shipping.yaml"
                        break;
                     case "4bc1299a-58ae-4c19-9533-b19c1b8ca57f":
                        return "apps/vertical-scaling/deployment.yaml"
                        break;
                     case "29495ece-204c-49ca-84e3-1066810cffeb":
                        return "apps/horizontal-scaling/deployment.yaml"
                        break;
                     case "c4e9324f-312f-4a1c-9d32-c8288d73626b":
                        return "apps/horizontal-scaling/hpa.yaml"
                        break;
                     default:
                       console.log(`issue wit id`);
                       return ""
                 }
               }
          EOT
        )
      })
      position {
        x = 0
        y = 1
      }
    }
    task {
      name        = "fetch_manifest"
      description = "Gets the content of the manifest"
      action      = "dynatrace.github.connector:get-content"
      active      = true
      input = jsonencode({
        owner        = "{{ result(\"find_manifest\").owner }}",
        repository   = "{{ result(\"find_manifest\").repository }}",
        filePath     = "{{ result(\"find_manifest\").filePath }}",
        reference    = "{{ result(\"find_manifest\").defaultBranch }}",
        connectionId = dynatrace_generic_setting.github_credentials.id
      })
      position {
        x = 0
        y = 2
      }
      conditions {
        states = {
          find_manifest = "OK"
        }
      }
    }
    task {
      name        = "apply_suggestions"
      description = "Uses the Davis CoPilot to apply all suggestions to the given manifest"
      action      = "dynatrace.automations:run-javascript"
      active      = true
      input = jsonencode({
        script = chomp(
          <<-EOT
          import {execution} from '@dynatrace-sdk/automation-utils';
          import {credentialVaultClient} from '@dynatrace-sdk/client-classic-environment-v2';
          import {getEnvironmentUrl} from '@dynatrace-sdk/app-environment'

          export default async function ({execution_id}) {
            const ex = await execution(execution_id);
            var manifest = (await ex.result('fetch_manifest')).content;
            const event = ex.params.event;

            const apiToken = await credentialVaultClient.getCredentialsDetails({
              id: "${dynatrace_credentials.dynatrace_platform_token.id}",
            }).then((credentials) => credentials.token);

            const url = `$${getEnvironmentUrl()}/platform/davis/copilot/v0.2/skills/conversations:message`;

            const response = await fetch(url, {
              method: 'POST',
              headers: {
                'Authorization': `Bearer $${apiToken}`,
                'Content-Type': 'application/json'
              },
              body: JSON.stringify({
                text: `$${event['kubernetes.predictivescaling.prediction.prompt']}\n\n$${manifest}`
              })
            }).then(response => response.json());

            return {
              manifest: response.text.match(/(?<=^```(yaml|yml).*\n)([^`])*(?=^```$)/gm)[0],
              time: new Date(event.timestamp).getTime(),
              description: event['kubernetes.predictivescaling.prediction.description']
            };
          }
          EOT
        )
      })
      position {
        x = 0
        y = 3
      }
      conditions {
        states = {
          fetch_manifest = "OK"
        }
      }
    }
    task {
      name        = "update_manifest"
      description = "Updates the given manifest and pushes it to a new branch on GitHub"
      action      = "dynatrace.github.connector:create-or-replace-file"
      active      = true
      input = jsonencode({
        owner : "{{ result(\"find_manifest\").owner }}",
        repository : "{{ result(\"find_manifest\").repository }}",
        createNewBranch : true
        sourceBranch : "{{ result(\"find_manifest\").defaultBranch }}",
        branch : "apply-davis-predictions-{{result(\"apply_suggestions\").time}}",
        filePath : "{{ result(\"find_manifest\").filePath }}",
        fileContent : "{{ result(\"apply_suggestions\").manifest }}",
        commitMessage : "Apply suggestions predicted by Davis AI:\n\n{{ result(\"apply_suggestions\").description }}",
        connectionId : dynatrace_generic_setting.github_credentials.id
      })
      position {
        x = 0
        y = 4
      }
      conditions {
        states = {
          apply_suggestions = "OK"
        }
      }
    }
    task {
      name        = "create_pull_request"
      description = "Creates a pull request that includes all suggested changes"
      action      = "dynatrace.github.connector:create-pull-request"
      active      = true
      input = jsonencode({
        owner        = "{{ result(\"find_manifest\").owner }}",
        repository   = "{{ result(\"find_manifest\").repository }}",
        sourceBranch = "apply-davis-predictions-{{result(\"apply_suggestions\").time}}",
        targetBranch = "{{ result(\"find_manifest\").defaultBranch }}"
        title        = "Apply suggestions predicted by Dynatrace Davis AI",
        description  = "{{ result(\"apply_suggestions\").description }}",
        connectionId = dynatrace_generic_setting.github_credentials.id
      })
      position {
        x = 0
        y = 5
      }
      conditions {
        states = {
          update_manifest = "OK"
        }
      }
    }
    task {
      name        = "create_suggestion_applied_event"
      description = "Trigger an event of type \"Custom Info\" and let other components react to it"
      action      = "dynatrace.automations:run-javascript"
      active      = true
      input = jsonencode({
        script = chomp(
          <<-EOT
          import {execution} from '@dynatrace-sdk/automation-utils';
          import {eventsClient, EventIngestEventType} from "@dynatrace-sdk/client-classic-environment-v2";

          export default async function ({execution_id}) {
            const ex = await execution(execution_id);
            const pullRequest = (await ex.result('create_pull_request')).pullRequest;
            const event = ex.params.event;

            const eventBody = {
              eventType: EventIngestEventType.CustomInfo,
              title: 'Applied Scaling Suggestion Because of Davis AI Prediction',
              entitySelector: `type(CLOUD_APPLICATION),entityName.equals("$${event['kubernetes.predictivescaling.workload.name']}"),namespaceName("$${event['kubernetes.predictivescaling.workload.namespace']}"),toRelationships.isClusterOfCa(type(KUBERNETES_CLUSTER),entityId("$${event['kubernetes.predictivescaling.workload.cluster.id']}"))`,
              properties: {
                'kubernetes.predictivescaling.type': 'SUGGEST_SCALING',

                // Workload
                'kubernetes.predictivescaling.workload.cluster.name': event['kubernetes.predictivescaling.workload.cluster.name'],
                'kubernetes.predictivescaling.workload.cluster.id': event['kubernetes.predictivescaling.workload.cluster.id'],
                'kubernetes.predictivescaling.workload.kind': event['kubernetes.predictivescaling.workload.kind'],
                'kubernetes.predictivescaling.workload.namespace': event['kubernetes.predictivescaling.workload.namespace'],
                'kubernetes.predictivescaling.workload.name': event['kubernetes.predictivescaling.workload.name'],
                'kubernetes.predictivescaling.workload.uuid': event['kubernetes.predictivescaling.workload.uuid'],
                'kubernetes.predictivescaling.workload.limits.cpu': event['kubernetes.predictivescaling.workload.limits.cpu'],
                'kubernetes.predictivescaling.workload.limits.memory': event['kubernetes.predictivescaling.workload.limits.memory'],

                // Prediction
                'kubernetes.predictivescaling.prediction.type': event['kubernetes.predictivescaling.prediction.type'],
                'kubernetes.predictivescaling.prediction.prompt': event['kubernetes.predictivescaling.prediction.prompt'],
                'kubernetes.predictivescaling.prediction.description': event['kubernetes.predictivescaling.prediction.description'],
                'kubernetes.predictivescaling.prediction.suggestions': event['kubernetes.predictivescaling.prediction.suggestions'],

                // Target Utilization
                'kubernetes.predictivescaling.targetutilization.cpu.min': event['kubernetes.predictivescaling.targetutilization.cpu.min'],
                'kubernetes.predictivescaling.targetutilization.cpu.max': event['kubernetes.predictivescaling.targetutilization.cpu.max'],
                'kubernetes.predictivescaling.targetutilization.cpu.point': event['kubernetes.predictivescaling.targetutilization.cpu.point'],
                'kubernetes.predictivescaling.targetutilization.memory.min': event['kubernetes.predictivescaling.targetutilization.memory.min'],
                'kubernetes.predictivescaling.targetutilization.memory.max': event['kubernetes.predictivescaling.targetutilization.memory.max'],
                'kubernetes.predictivescaling.targetutilization.memory.point': event['kubernetes.predictivescaling.targetutilization.memory.point'],

                // Target
                'kubernetes.predictivescaling.target.uuid': event['kubernetes.predictivescaling.target.uuid'],
                'kubernetes.predictivescaling.target.repository': event['kubernetes.predictivescaling.target.repository'],

                // Pull Request
                'kubernetes.predictivescaling.pullrequest.id': `$${pullRequest.id}`,
                'kubernetes.predictivescaling.pullrequest.url': pullRequest.url,
              },
            };

            await eventsClient.createEvent({body: eventBody});
            return eventBody;
          }
          EOT
        )
      })
      position {
        x = 0
        y = 6
      }
      conditions {
        states = {
          create_pull_request = "OK"
        }
      }
    }
  }
  trigger {
    event {
      active = true
      config {
        event {
          event_type = "events"
          query      = "kubernetes.predictivescaling.type == \"DETECT_SCALING\""
        }
      }
    }
  }
}