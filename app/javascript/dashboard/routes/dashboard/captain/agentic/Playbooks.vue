<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import Button from 'dashboard/components-next/button/Button.vue';
import PlaybookCanvas from 'dashboard/components-next/captain/playbooks/PlaybookCanvas.vue';
import PlaybooksAPI from 'dashboard/api/captain/playbooks';
import AssistantAPI from 'dashboard/api/captain/assistant';

const { t } = useI18n();
const { accountId } = useAccount();
const playbooks = ref([]);
const assistants = ref([]);
const selected = ref(null);
const runs = ref([]);
const busy = ref(false);
const error = ref('');
const name = ref('');
const assistantId = ref(null);
const contains = ref('');
const automatic = ref(false);
const conversationId = ref(null);
const testContext = ref('{}');
const activeRun = ref(null);
const showRemove = ref(false);
const graph = computed(
  () => selected.value?.graph_definition || { nodes: [], edges: [] }
);

async function load() {
  const account = accountId.value;
  busy.value = true;
  error.value = '';
  try {
    const [playbooksResponse, assistantsResponse] = await Promise.all([
      PlaybooksAPI.get(),
      AssistantAPI.get(),
    ]);
    if (account !== accountId.value) return;
    playbooks.value = playbooksResponse.data.payload;
    assistants.value = assistantsResponse.data.payload;
  } catch {
    if (account === accountId.value)
      error.value = t('CAPTAIN.AGENTIC.LOAD_ERROR');
  } finally {
    if (account === accountId.value) busy.value = false;
  }
}

async function runRequest(request, onSuccess) {
  const account = accountId.value;
  busy.value = true;
  error.value = '';
  try {
    const { data } = await request();
    if (account === accountId.value) onSuccess(data);
  } catch {
    if (account === accountId.value)
      error.value = t('CAPTAIN.AGENTIC.REQUEST_ERROR');
  } finally {
    if (account === accountId.value) busy.value = false;
  }
}

function setSelected(playbook) {
  selected.value = playbook;
  name.value = playbook.name;
  assistantId.value = playbook.assistant_id;
  contains.value = playbook.trigger_conditions?.message_contains || '';
  automatic.value = playbook.trigger_conditions?.automatic === true;
  const index = playbooks.value.findIndex(item => item.id === playbook.id);
  if (index < 0) playbooks.value.unshift(playbook);
  else playbooks.value.splice(index, 1, playbook);
}

function open(playbook) {
  setSelected(playbook);
  showRemove.value = false;
  runs.value = [];
  activeRun.value = null;
  return runRequest(
    () => PlaybooksAPI.runs(playbook.id),
    data => {
      runs.value = data.payload;
    }
  );
}

function create() {
  return runRequest(
    () =>
      PlaybooksAPI.create({
        name: name.value.trim(),
        assistant_id: assistantId.value,
      }),
    setSelected
  );
}

function saveDefinition(definition) {
  return runRequest(
    () =>
      PlaybooksAPI.update(selected.value.id, { graph_definition: definition }),
    setSelected
  );
}

function saveSettings() {
  return runRequest(
    () =>
      PlaybooksAPI.update(selected.value.id, {
        name: name.value.trim(),
        trigger_conditions: {
          automatic: automatic.value,
          message_contains: contains.value.trim(),
        },
      }),
    setSelected
  );
}

function publish() {
  return runRequest(() => PlaybooksAPI.publish(selected.value.id), setSelected);
}

function clearSelection() {
  selected.value = null;
  name.value = '';
  assistantId.value = null;
  contains.value = '';
  automatic.value = false;
  runs.value = [];
  activeRun.value = null;
  showRemove.value = false;
}

function remove() {
  const id = selected.value.id;
  return runRequest(
    () => PlaybooksAPI.delete(id),
    () => {
      playbooks.value = playbooks.value.filter(item => item.id !== id);
      clearSelection();
    }
  );
}

async function dryRun() {
  let context;
  try {
    context = JSON.parse(testContext.value);
    if (!context || Array.isArray(context) || typeof context !== 'object') {
      throw new TypeError();
    }
  } catch {
    error.value = t('CAPTAIN.AGENTIC.INVALID_JSON');
    return;
  }
  await runRequest(
    () =>
      PlaybooksAPI.execute(selected.value.id, conversationId.value, context),
    data => {
      activeRun.value = data;
      runs.value.unshift(data);
    }
  );
}

watch(
  accountId,
  () => {
    clearSelection();
    playbooks.value = [];
    assistants.value = [];
    conversationId.value = null;
    testContext.value = '{}';
    load();
  },
  { immediate: true }
);
</script>

<template>
  <main class="h-full w-full overflow-y-auto px-4 py-6">
    <div class="mx-auto max-w-5xl space-y-4">
      <h1 class="text-xl font-semibold text-n-slate-12">
        {{ $t('CAPTAIN.AGENTIC.NAV.PLAYBOOKS') }}
      </h1>
      <p class="text-sm text-n-slate-11">
        {{ $t('CAPTAIN.AGENTIC.PLAYBOOKS.DESCRIPTION') }}
      </p>
      <p v-if="error" role="alert" class="text-sm text-n-ruby-11">
        {{ error }}
      </p>
      <div class="grid gap-4 md:grid-cols-[14rem_1fr]">
        <aside class="space-y-2">
          <Button
            variant="outline"
            :disabled="busy"
            :label="$t('CAPTAIN.AGENTIC.PLAYBOOKS.NEW')"
            @click="clearSelection"
          />
          <button
            v-for="playbook in playbooks"
            :key="playbook.id"
            type="button"
            :disabled="busy"
            :aria-current="selected?.id === playbook.id ? 'true' : undefined"
            class="block w-full rounded-md border border-n-weak p-2 text-start text-sm"
            @click="open(playbook)"
          >
            <span>{{ playbook.name }}</span>
            <span class="block text-xs text-n-slate-11">{{
              playbook.status
            }}</span>
          </button>
        </aside>
        <section class="min-w-0 space-y-4">
          <form
            class="space-y-3 rounded-lg border border-n-weak p-4"
            @submit.prevent="selected ? saveSettings() : create()"
          >
            <label class="block text-sm">
              {{ $t('CAPTAIN.AGENTIC.NAME') }}
              <input
                v-model="name"
                type="text"
                required
                maxlength="150"
                class="block w-full rounded-md"
              />
            </label>
            <label v-if="!selected" class="block text-sm">
              {{ $t('CAPTAIN.AGENTIC.PLAYBOOKS.ASSISTANT') }}
              <select
                v-model="assistantId"
                class="block w-full rounded-md"
                required
              >
                <option :value="null" disabled>
                  {{ $t('CAPTAIN.AGENTIC.PLAYBOOKS.SELECT_ASSISTANT') }}
                </option>
                <option
                  v-for="assistant in assistants"
                  :key="assistant.id"
                  :value="assistant.id"
                >
                  {{ assistant.name }}
                </option>
              </select>
            </label>
            <template v-else>
              <label class="flex items-center gap-2 text-sm">
                <input v-model="automatic" type="checkbox" />
                {{ $t('CAPTAIN.AGENTIC.PLAYBOOKS.AUTOMATIC') }}
              </label>
              <label class="block text-sm">
                {{ $t('CAPTAIN.AGENTIC.PLAYBOOKS.CONTAINS') }}
                <input
                  v-model="contains"
                  type="text"
                  class="block w-full rounded-md"
                />
              </label>
            </template>
            <Button
              type="submit"
              :disabled="busy || !name.trim() || !assistantId"
              :label="
                selected
                  ? $t('CAPTAIN.AGENTIC.SAVE')
                  : $t('CAPTAIN.AGENTIC.PLAYBOOKS.CREATE')
              "
            />
          </form>
          <template v-if="selected">
            <section class="space-y-3 rounded-lg border border-n-weak p-4">
              <p class="text-sm">
                {{
                  $t('CAPTAIN.AGENTIC.PLAYBOOKS.VERSION', {
                    version: selected.version,
                    status: selected.status,
                  })
                }}
              </p>
              <PlaybookCanvas
                :graph="graph"
                :busy="busy"
                @save="saveDefinition"
              />
              <div class="flex flex-wrap gap-2 border-t border-n-weak pt-3">
                <Button
                  :disabled="busy"
                  :label="$t('CAPTAIN.AGENTIC.PLAYBOOKS.PUBLISH')"
                  @click="publish"
                />
                <Button
                  variant="outline"
                  color="ruby"
                  :disabled="busy"
                  :label="
                    showRemove
                      ? $t('CAPTAIN.AGENTIC.CONFIRM_REMOVE')
                      : $t('CAPTAIN.AGENTIC.REMOVE')
                  "
                  @click="showRemove ? remove() : (showRemove = true)"
                />
              </div>
            </section>
            <section class="space-y-3 rounded-lg border border-n-weak p-4">
              <h2 class="text-base font-semibold">
                {{ $t('CAPTAIN.AGENTIC.PLAYBOOKS.RUNS') }}
              </h2>
              <form class="space-y-3" @submit.prevent="dryRun">
                <label class="block text-sm">
                  {{ $t('CAPTAIN.AGENTIC.PLAYBOOKS.CONVERSATION') }}
                  <input
                    v-model.number="conversationId"
                    type="number"
                    min="1"
                    required
                    class="block rounded-md"
                  />
                </label>
                <label class="block text-sm">
                  {{ $t('CAPTAIN.AGENTIC.PLAYBOOKS.CONTEXT') }}
                  <textarea
                    v-model="testContext"
                    rows="3"
                    spellcheck="false"
                    class="block w-full rounded-md font-mono text-xs"
                  />
                </label>
                <Button
                  type="submit"
                  :disabled="busy || !conversationId"
                  :label="$t('CAPTAIN.AGENTIC.PLAYBOOKS.DRY_RUN')"
                />
              </form>
              <button
                v-for="run in runs"
                :key="run.id"
                type="button"
                class="block w-full rounded-md border border-n-weak p-2 text-start text-sm"
                @click="activeRun = run"
              >
                {{
                  $t('CAPTAIN.AGENTIC.PLAYBOOKS.RUN_LABEL', {
                    id: run.id,
                    status: run.status,
                  })
                }}
              </button>
              <pre
                v-if="activeRun"
                class="max-h-96 overflow-auto rounded-md bg-n-alpha-1 p-3 text-xs"
                >{{ JSON.stringify(activeRun.execution_trace, null, 2) }}
              </pre>
            </section>
          </template>
        </section>
      </div>
    </div>
  </main>
</template>
