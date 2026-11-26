class CreateCaptainAgenticPlatform < ActiveRecord::Migration[8.0]
  def change
    create_playbooks
    create_playbook_runs
    create_action_approvals
    create_llm_provider_configs
    create_simulation_runs
    create_simulation_results
    create_swarm_handoffs
    create_kb_proposals
    create_resolution_events
  end

  private

  def create_playbooks
    create_table :captain_playbooks do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :assistant, null: false, foreign_key: { to_table: :captain_assistants, on_delete: :cascade }
      t.string :name, null: false
      t.text :description
      t.integer :version, null: false, default: 1
      t.string :status, null: false, default: 'draft'
      t.jsonb :trigger_conditions, null: false, default: {}
      t.jsonb :graph_definition, null: false, default: { nodes: [], edges: [] }
      t.timestamps
    end
  end

  def create_playbook_runs
    create_table :captain_playbook_runs do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :playbook, null: false, foreign_key: { to_table: :captain_playbooks, on_delete: :cascade }
      t.references :conversation, foreign_key: { on_delete: :cascade }
      t.string :status, null: false, default: 'running'
      t.string :current_node_id
      t.jsonb :context_state, null: false, default: {}
      t.jsonb :execution_trace, null: false, default: []
      t.jsonb :graph_snapshot, null: false, default: {}
      t.bigint :trigger_message_id
      t.boolean :dry_run, null: false, default: false
      t.timestamps
    end
    add_index :captain_playbook_runs, %i[playbook_id trigger_message_id],
              unique: true, where: 'trigger_message_id IS NOT NULL', name: 'idx_captain_playbook_runs_trigger'
  end

  def create_action_approvals
    create_table :captain_action_approvals do |t|
      t.references :account, :conversation, null: false, foreign_key: { on_delete: :cascade }
      t.references :assistant, null: false, foreign_key: { to_table: :captain_assistants, on_delete: :cascade }
      t.references :reviewer, foreign_key: { to_table: :users, on_delete: :nullify }
      approval_tool_columns(t)
      t.string :tool_name, null: false
      t.string :risk_level, null: false, default: 'high'
      t.string :status, null: false, default: 'pending'
      t.jsonb :proposed_arguments, null: false, default: {}
      t.jsonb :modified_arguments
      t.jsonb :execution_result, default: {}
      t.text :rationale
      t.text :rejection_reason
      t.datetime :expires_at, null: false
      t.datetime :reviewed_at, :executed_at
      t.timestamps
    end
    add_index :captain_action_approvals, %i[account_id status]
  end

  def approval_tool_columns(table)
    table.references :playbook_run, foreign_key: { to_table: :captain_playbook_runs, on_delete: :nullify }
    table.references :mcp_tool, foreign_key: { to_table: :captain_mcp_tools, on_delete: :nullify }
    table.references :custom_tool, foreign_key: { to_table: :captain_custom_tools, on_delete: :nullify }
    table.string :tool_definition_digest
    table.bigint :responding_to_message_id
  end

  def create_llm_provider_configs
    create_table :captain_llm_provider_configs do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.string :provider_type, null: false
      t.string :model_id, null: false
      t.string :endpoint_url
      t.string :region
      t.text :encrypted_credentials
      t.boolean :zero_data_retention, null: false, default: false
      t.integer :priority, null: false, default: 1
      t.boolean :enabled, null: false, default: true
      t.jsonb :routing_rules, null: false, default: {}
      t.timestamps
    end
    add_index :captain_llm_provider_configs, %i[account_id priority]
  end

  def create_simulation_runs
    create_table :captain_simulation_runs do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :assistant, null: false, foreign_key: { to_table: :captain_assistants, on_delete: :cascade }
      t.references :playbook, foreign_key: { to_table: :captain_playbooks, on_delete: :nullify }
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :status, null: false, default: 'queued'
      t.jsonb :candidate_config, null: false, default: {}
      t.jsonb :ticket_ids, null: false, default: []
      t.jsonb :ticket_filter, null: false, default: {}
      t.integer :total_tickets, null: false, default: 0
      t.integer :processed_tickets, null: false, default: 0
      t.jsonb :aggregate_metrics, null: false, default: {}
      t.datetime :started_at, :completed_at
      t.timestamps
    end
  end

  def create_simulation_results
    create_table :captain_simulation_results do |t|
      t.references :simulation_run, null: false, foreign_key: { to_table: :captain_simulation_runs, on_delete: :cascade }
      t.references :conversation, null: false, foreign_key: { on_delete: :cascade }
      t.text :simulated_response
      t.jsonb :simulated_tool_calls, null: false, default: []
      t.boolean :projected_deflection, null: false, default: false
      t.float :hallucination_score, null: false, default: 0.0
      t.float :policy_adherence_score, null: false, default: 1.0
      t.text :judge_rationale
      t.timestamps
    end
    add_index :captain_simulation_results, %i[simulation_run_id conversation_id], unique: true,
                                                                                  name: 'idx_captain_simulation_results_run_conversation'
  end

  def create_swarm_handoffs
    add_column :captain_assistants, :swarm_role, :string
    add_column :captain_assistants, :swarm_capabilities, :jsonb, default: [], null: false
    add_index :captain_assistants, %i[account_id swarm_role], unique: true, where: 'swarm_role IS NOT NULL'
    add_reference :captain_assistants, :llm_provider_config, foreign_key: { to_table: :captain_llm_provider_configs, on_delete: :nullify }

    create_table :captain_swarm_handoffs do |t|
      t.references :account, :conversation, null: false, foreign_key: { on_delete: :cascade }
      t.references :from_assistant, foreign_key: { to_table: :captain_assistants, on_delete: :nullify }
      t.references :to_assistant, foreign_key: { to_table: :captain_assistants, on_delete: :nullify }
      t.string :handoff_type, null: false
      t.integer :hop_count, null: false, default: 1
      t.jsonb :structured_context, null: false, default: {}
      t.text :root_cause_brief
      t.timestamps
    end
  end

  def create_kb_proposals
    create_table :captain_kb_proposals do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :portal, null: false, foreign_key: { on_delete: :cascade }
      t.references :target_article, foreign_key: { to_table: :articles, on_delete: :nullify }
      t.references :reviewer, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :proposal_type, null: false
      t.string :status, null: false, default: 'open'
      t.string :proposed_title, null: false
      t.text :proposed_markdown, null: false
      t.text :unified_diff
      t.jsonb :source_conversation_ids, null: false, default: []
      t.string :target_article_digest
      t.string :source_digest
      t.float :confidence_score, null: false, default: 0.0
      t.vector :cluster_centroid, limit: 1536
      t.timestamps
    end
    add_index :captain_kb_proposals, %i[account_id portal_id source_digest], unique: true,
                                                                             name: 'idx_captain_kb_proposals_source'
  end

  def create_resolution_events
    create_table :captain_resolution_events do |t|
      t.references :account, :conversation, null: false, foreign_key: { on_delete: :cascade }
      t.references :assistant, foreign_key: { to_table: :captain_assistants, on_delete: :nullify }
      t.string :resolution_actor, null: false
      t.string :verification_status, null: false, default: 'pending'
      t.decimal :estimated_human_cost_usd, precision: 10, scale: 2, default: 6.50
      t.decimal :billable_fee_usd, precision: 10, scale: 4, default: 0.0
      t.integer :csat_rating
      t.string :stripe_meter_event_id
      t.datetime :episode_started_at, null: false
      t.datetime :resolved_at, null: false
      t.datetime :verified_at
      t.timestamps
    end
    add_index :captain_resolution_events, %i[account_id verification_status resolved_at],
              name: 'idx_captain_resolutions_account_status_date'
    add_index :captain_resolution_events, %i[conversation_id resolved_at], unique: true
  end
end
