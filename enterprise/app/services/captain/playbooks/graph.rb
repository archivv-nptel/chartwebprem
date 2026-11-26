class Captain::Playbooks::Graph
  MAX_NODES = 25
  MAX_EDGES = 75
  FIELD = /\A\w+(?:\.\w+)*\z/
  LABELS = {
    'trigger' => %w[default],
    'condition' => %w[true false],
    'otp_verify' => %w[default verified error],
    'hitl_gate' => %w[default success error rejected],
    'mcp_tool' => %w[default success error rejected],
    'llm_reason' => %w[default],
    'reply' => %w[default],
    'escalate' => []
  }.freeze
  OPERATORS = %w[eq lte gte in].freeze

  def initialize(definition)
    @definition = definition
  end

  def problem(require_nodes: false)
    return 'must contain nodes and edges arrays' unless graph_shape?

    limits_problem(require_nodes) || structure_problem || (publication_problem if require_nodes)
  end

  def entry
    nodes.find { |node| node['type'] == 'trigger' } || nodes.find { |node| incoming[node['id']].blank? }
  end

  def node(node_id)
    node_map.fetch(node_id)
  end

  def next_node_id(source, branch)
    successors = outgoing.fetch(source, [])
    edge = successors.find { |candidate| label(candidate) == branch }
    edge ||= successors.find { |candidate| label(candidate) == 'default' } if %w[success verified].include?(branch)
    edge&.fetch('target')
  end

  private

  def limits_problem(require_nodes)
    return 'must contain at least one node before publication' if require_nodes && nodes.empty?
    return "exceeds the limit of #{MAX_NODES} nodes or #{MAX_EDGES} edges" if nodes.size > MAX_NODES || edges.size > MAX_EDGES
  end

  def publication_problem
    'condition nodes must have true and false branches' unless complete_branches?
  end

  def structure_problem
    return 'contains an invalid node or duplicate node ID' unless valid_nodes?
    return 'contains an invalid edge or ambiguous branch' unless valid_edges?
    return 'must have one entry node and all nodes reachable without cycles' unless connected_dag?
  end

  def nodes
    @definition['nodes']
  end

  def edges
    @definition['edges']
  end

  def graph_shape?
    @definition.is_a?(Hash) && nodes.is_a?(Array) && edges.is_a?(Array)
  end

  def valid_nodes?
    nodes.all? { |node| valid_node?(node) } && node_map.size == nodes.size && nodes.count { |node| node['type'] == 'trigger' } <= 1
  end

  def valid_node?(node)
    return false unless node.is_a?(Hash) && node['id'].is_a?(String) && node['id'].match?(/\A[\w-]{1,64}\z/) && LABELS.key?(node['type'])

    config = node.fetch('config', {})
    config.is_a?(Hash) && valid_configuration?(node['type'], config)
  end

  def valid_configuration?(type, config)
    case type
    when 'condition' then valid_condition?(config)
    when 'mcp_tool', 'hitl_gate'
      valid_tool_configuration?(config)
    when 'llm_reason'
      valid_reasoning_configuration?(config)
    when 'reply' then text?(config['template'], 10_000)
    else true
    end
  end

  def valid_tool_configuration?(config)
    server_id = config['mcp_server_id']
    server_id.is_a?(Integer) && server_id.positive? && text?(config['tool_name'], 128) &&
      config.fetch('arguments', {}).is_a?(Hash)
  end

  def valid_reasoning_configuration?(config)
    output_key = config.fetch('output_key', 'llm_output')
    output_key.is_a?(String) && output_key.match?(/\A[a-zA-Z]\w{0,63}\z/) &&
      %w[captain_message_id customer_message last_reply tool_output].exclude?(output_key) &&
      text?(config['user_prompt'], 10_000) && config.fetch('system_prompt', '').is_a?(String) &&
      valid_temperature?(config.fetch('temperature', 0.2))
  end

  def valid_condition?(config)
    return false unless config['field'].is_a?(String) && FIELD.match?(config['field']) && OPERATORS.include?(config['operator'])

    return config['value'].is_a?(Numeric) if %w[lte gte].include?(config['operator'])
    return config['value'].is_a?(Array) if config['operator'] == 'in'

    config.key?('value')
  end

  def text?(value, max)
    value.is_a?(String) && value.present? && value.length <= max
  end

  def valid_temperature?(value)
    value.is_a?(Numeric) && value.between?(0, 2)
  end

  def valid_edges?
    edges.all? { |edge| valid_edge?(edge) } && edges.uniq { |edge| [edge['source'], label(edge)] }.size == edges.size
  end

  def valid_edge?(edge)
    return false unless edge.is_a?(Hash) && node_map.key?(edge['source']) && node_map.key?(edge['target'])

    LABELS.fetch(node_map.fetch(edge['source']).fetch('type')).include?(label(edge))
  end

  def label(edge)
    edge.fetch('label', 'default')
  end

  def incoming
    @incoming ||= edges.group_by { |edge| edge['target'] }
  end

  def outgoing
    @outgoing ||= edges.group_by { |edge| edge['source'] }
  end

  def node_map
    @node_map ||= nodes.index_by { |node| node['id'] }
  end

  def connected_dag?
    return true if nodes.empty?

    roots = nodes.reject { |node| incoming.key?(node['id']) }
    return false unless roots == [entry]

    reachable_node_count(roots.pluck('id')) == nodes.size
  end

  def reachable_node_count(queue)
    counts = incoming.transform_values(&:size)
    queue.each do |id|
      outgoing.fetch(id, []).each do |edge|
        target = edge.fetch('target')
        counts[target] -= 1
        queue << target if counts[target].zero?
      end
    end
    queue.size
  end

  def complete_branches?
    nodes.select { |node| node['type'] == 'condition' }.all? do |node|
      outgoing.fetch(node['id'], []).map { |edge| label(edge) }.sort == %w[false true]
    end
  end
end
