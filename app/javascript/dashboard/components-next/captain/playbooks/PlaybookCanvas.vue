<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  graph: { type: Object, required: true },
  busy: { type: Boolean, default: false },
});
const emit = defineEmits(['save']);
const { t } = useI18n();
const draft = ref('');
const nodeType = ref('trigger');
const sourceId = ref('');
const branch = ref('');
const error = ref('');

const nodeTemplates = {
  trigger: {},
  condition: { field: 'order.amount', operator: 'lte', value: 100 },
  otp_verify: {},
  hitl_gate: { mcp_server_id: null, tool_name: '', arguments: {} },
  mcp_tool: { mcp_server_id: null, tool_name: '', arguments: {} },
  llm_reason: { system_prompt: '', user_prompt: '{{customer_message}}' },
  reply: { template: '' },
  escalate: { reason: '' },
};

const sourceBranches = {
  condition: ['true', 'false'],
  mcp_tool: ['success', 'error', 'rejected'],
  hitl_gate: ['success', 'error', 'rejected'],
  otp_verify: ['verified', 'error'],
  escalate: [],
};
const editableGraph = computed(() => {
  try {
    const graph = JSON.parse(draft.value);
    if (Array.isArray(graph?.nodes) && Array.isArray(graph?.edges))
      return graph;
  } catch {
    // Keep the draft editable while its JSON is incomplete.
  }
  return null;
});
const graphNodes = computed(() =>
  (editableGraph.value?.nodes || []).filter(node => node?.id)
);
const connectableNodes = computed(() =>
  graphNodes.value.filter(node => node.type !== 'escalate')
);
const sourceNode = computed(() =>
  connectableNodes.value.find(node => node.id === sourceId.value)
);
const availableBranches = computed(() => {
  if (!sourceNode.value) return [];
  const configured = sourceBranches[sourceNode.value.type] || ['default'];
  const allocated = editableGraph.value.edges
    .filter(edge => edge?.source === sourceId.value)
    .map(edge => {
      const label = edge.label || 'default';
      return label === 'default' ? configured[0] : label;
    });
  return configured.filter(label => !allocated.includes(label));
});

watch(availableBranches, labels => {
  if (!labels.includes(branch.value)) branch.value = labels[0] || '';
});
watch(
  () => props.graph,
  graph => {
    draft.value = JSON.stringify(graph, null, 2);
    sourceId.value = graph.nodes?.at(-1)?.id || '';
    nodeType.value = graph.nodes?.length ? 'reply' : 'trigger';
    error.value = '';
  },
  { immediate: true }
);

function parseGraph() {
  error.value = editableGraph.value
    ? ''
    : t('CAPTAIN.AGENTIC.PLAYBOOKS.INVALID_GRAPH');
  return editableGraph.value;
}

function addNode() {
  const graph = parseGraph();
  if (!graph) return;

  const type = nodeType.value;
  const id = crypto.randomUUID();
  graph.nodes.push({ id, type, config: nodeTemplates[type] });
  if (sourceNode.value && branch.value) {
    graph.edges.push({
      source: sourceId.value,
      target: id,
      label: branch.value,
    });
  }
  draft.value = JSON.stringify(graph, null, 2);
  sourceId.value = id;
  if (type === 'trigger') nodeType.value = 'reply';
}

function save() {
  const graph = parseGraph();
  if (graph) emit('save', graph);
}
</script>

<template>
  <div class="space-y-3">
    <div class="flex flex-wrap items-end gap-2">
      <label class="block text-sm">
        {{ $t('CAPTAIN.AGENTIC.PLAYBOOKS.NODE_TYPE') }}
        <select v-model="nodeType" class="block rounded-md">
          <option
            v-for="(_, type) in nodeTemplates"
            :key="type"
            :value="type"
            :disabled="type === 'trigger' && !!editableGraph?.nodes.length"
          >
            {{ type }}
          </option>
        </select>
      </label>
      <label v-if="connectableNodes.length" class="block text-sm">
        {{ $t('CAPTAIN.AGENTIC.PLAYBOOKS.CONNECT_FROM') }}
        <select v-model="sourceId" class="block max-w-48 rounded-md">
          <option value="">
            {{ $t('CAPTAIN.AGENTIC.PLAYBOOKS.NO_CONNECTION') }}
          </option>
          <option
            v-for="node in connectableNodes"
            :key="node.id"
            :value="node.id"
          >
            {{
              $t('CAPTAIN.AGENTIC.PLAYBOOKS.NODE_LABEL', {
                type: node.type,
                id: node.id,
              })
            }}
          </option>
        </select>
      </label>
      <label v-if="availableBranches.length" class="block text-sm">
        {{ $t('CAPTAIN.AGENTIC.PLAYBOOKS.BRANCH') }}
        <select v-model="branch" class="block rounded-md">
          <option
            v-for="label in availableBranches"
            :key="label"
            :value="label"
          >
            {{ label }}
          </option>
        </select>
      </label>
      <Button
        variant="outline"
        :disabled="busy || (!!sourceNode && !branch)"
        :label="$t('CAPTAIN.AGENTIC.PLAYBOOKS.ADD_NODE')"
        @click="addNode"
      />
    </div>
    <ul v-if="graphNodes.length" class="flex flex-wrap gap-2">
      <li
        v-for="node in graphNodes"
        :key="node.id"
        class="rounded-md border border-n-weak px-2 py-1 text-xs"
      >
        {{
          $t('CAPTAIN.AGENTIC.PLAYBOOKS.NODE_LABEL', {
            type: node.type,
            id: node.id,
          })
        }}
      </li>
    </ul>
    <label class="block text-sm">
      {{ $t('CAPTAIN.AGENTIC.PLAYBOOKS.GRAPH') }}
      <span class="block text-xs text-n-slate-11">{{
        $t('CAPTAIN.AGENTIC.PLAYBOOKS.GRAPH_HELP')
      }}</span>
      <textarea
        v-model="draft"
        rows="12"
        spellcheck="false"
        :disabled="busy"
        class="mt-1 w-full rounded-md border border-n-weak font-mono text-xs"
      />
    </label>
    <p v-if="error" role="alert" class="text-sm text-n-ruby-11">{{ error }}</p>
    <Button
      :disabled="busy"
      :label="$t('CAPTAIN.AGENTIC.PLAYBOOKS.SAVE_GRAPH')"
      @click="save"
    />
  </div>
</template>
