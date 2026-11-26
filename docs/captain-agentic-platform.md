# Captain agentic workflows

Run `bundle exec rails db:migrate` before enabling these Enterprise features. Deploy the Rails web and Sidekiq processes with the same configuration. The flags are off by default and can be enabled per account in Super Admin. Enable Captain and connect an assistant to an inbox before exercising a live conversation workflow.

| Account feature | Where to start |
| --- | --- |
| `captain_hitl_approvals` | Review pending tool requests in the conversation. A change to the customer turn or approved tool definition can prevent execution. |
| `captain_mcp_servers` and `captain_mcp_enterprise` | Configure the outbound registry in Captain Tools. The separate inbound flag enables the [MCP API](captain-enterprise-mcp.md). |
| `captain_agentic_playbooks` | In Captain Playbooks, create a graph, test it on a conversation and publish it. Enable tool approval before using a graph that can change an external system. |
| `captain_byom_routing` | Add and test a model provider in Captain Model Providers. Set priorities and optionally choose a preferred provider in assistant settings. |
| `captain_simulations` | In Captain Simulations, select an assistant, a sample of resolved conversations, and an optional playbook. The simulation calls the model but skips live tools and customer replies. |
| `captain_swarm_handoffs` | Give assistants distinct roles and describe what each role can handle under the assistant's system settings. |
| `captain_self_healing_kb` | Link an inbox to an active Help Center portal. The scheduler queues a weekly scan of recent knowledge gaps. Review and merge drafts under Knowledge Proposals. |
| `captain_outcome_metering` | The Resolution Outcomes page reports verified resolutions, estimated savings and fees, and CSAT parity. Only explicitly attributed Captain outcomes can become billable. |

Configure the existing Active Record encryption keys before saving MCP or model provider credentials. The provider setting for zero data retention reflects the terms of your provider agreement. It keeps failover on providers marked for the same requirement.

To send verified outcomes to Stripe, set `CAPTAIN_STRIPE_METER_EVENT_NAME` to the event name on an existing Stripe usage meter. The meter must accept `stripe_customer_id` and `value` fields. The job also requires the installation's `STRIPE_SECRET_KEY` and the account's saved Stripe customer ID. Specify prices in Stripe. The dashboard's estimated fees are calculated from the local outcome ledger.

To compile the deployment assets, run `bundle exec rails assets:precompile` with the production environment and the project's pinned Node and pnpm versions. Run `bundle exec rails zeitwerk:check` to check backend loading.
