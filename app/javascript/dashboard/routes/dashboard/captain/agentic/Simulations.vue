<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { usePolicy } from 'dashboard/composables/usePolicy';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import Button from 'dashboard/components-next/button/Button.vue';
import AssistantAPI from 'dashboard/api/captain/assistant';
import PlaybooksAPI from 'dashboard/api/captain/playbooks';
import SimulationsAPI from 'dashboard/api/captain/simulations';

const { t } = useI18n();
const { accountId } = useAccount();
const { isFeatureFlagEnabled } = usePolicy();
const assistants = ref([]);
const playbooks = ref([]);
const runs = ref([]);
const selected = ref(null);
const assistantId = ref(null);
const playbookId = ref(null);
const prompt = ref('');
const model = ref('');
const limit = ref(20);
const inboxId = ref(null);
const error = ref('');
const busy = ref(false);
const page = ref(1);
const pageSize = 100;
const eligiblePlaybooks = computed(() =>
  playbooks.value.filter(
    playbook => playbook.assistant_id === assistantId.value
  )
);

async function request(callback) {
  const account = accountId.value;
  busy.value = true;
  error.value = '';
  try {
    await callback(() => account === accountId.value);
  } catch {
    if (account === accountId.value)
      error.value = t('CAPTAIN.AGENTIC.REQUEST_ERROR');
  } finally {
    if (account === accountId.value) busy.value = false;
  }
}

function load() {
  return request(async isCurrent => {
    const [assistantResponse, runResponse, playbookResponse] =
      await Promise.all([
        AssistantAPI.get(),
        SimulationsAPI.get(),
        isFeatureFlagEnabled(FEATURE_FLAGS.CAPTAIN_AGENTIC_PLAYBOOKS)
          ? PlaybooksAPI.get()
          : null,
      ]);
    if (!isCurrent()) return;
    assistants.value = assistantResponse.data.payload;
    playbooks.value = playbookResponse?.data.payload || [];
    runs.value = runResponse.data.payload;
  });
}

function applyRun(run, nextPage) {
  selected.value = run;
  page.value = nextPage;
  const index = runs.value.findIndex(item => item.id === run.id);
  if (index === -1) runs.value.unshift(run);
  else runs.value.splice(index, 1, run);
}

function show(id, nextPage = 1) {
  return request(async isCurrent => {
    const { data } = await SimulationsAPI.show(id, nextPage);
    if (isCurrent()) applyRun(data, nextPage);
  });
}

function create() {
  const payload = {
    assistant_id: assistantId.value,
    ticket_filter: { limit: limit.value },
    candidate_config: {},
  };
  if (playbookId.value) payload.playbook_id = playbookId.value;
  if (inboxId.value) payload.ticket_filter.inbox_id = inboxId.value;
  if (prompt.value.trim())
    payload.candidate_config.system_prompt = prompt.value.trim();
  if (model.value.trim())
    payload.candidate_config.model_id = model.value.trim();
  return request(async isCurrent => {
    const { data } = await SimulationsAPI.create(payload);
    if (isCurrent()) applyRun(data, 1);
  });
}

watch(assistantId, () => {
  playbookId.value = null;
});
watch(
  accountId,
  () => {
    assistants.value = [];
    playbooks.value = [];
    runs.value = [];
    selected.value = null;
    assistantId.value = null;
    prompt.value = '';
    model.value = '';
    inboxId.value = null;
    limit.value = 20;
    load();
  },
  { immediate: true }
);
</script>

<template>
  <main class="h-full w-full overflow-y-auto px-4 py-6">
    <div class="mx-auto max-w-5xl space-y-4">
      <h1 class="text-xl font-semibold">
        {{ $t('CAPTAIN.AGENTIC.NAV.SIMULATIONS') }}
      </h1>
      <p class="text-sm text-n-slate-11">
        {{ $t('CAPTAIN.AGENTIC.SIMULATIONS.DESCRIPTION') }}
      </p>
      <p v-if="error" role="alert" class="text-sm text-n-ruby-11">
        {{ error }}
      </p>
      <form
        class="space-y-3 rounded-lg border border-n-weak p-4"
        @submit.prevent="create"
      >
        <label class="block text-sm">
          {{ $t('CAPTAIN.AGENTIC.SIMULATIONS.ASSISTANT') }}
          <select
            v-model="assistantId"
            required
            class="block w-full rounded-md"
          >
            <option :value="null" disabled>
              {{ $t('CAPTAIN.AGENTIC.SIMULATIONS.SELECT_ASSISTANT') }}
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
        <label v-if="eligiblePlaybooks.length" class="block text-sm">
          {{ $t('CAPTAIN.AGENTIC.SIMULATIONS.PLAYBOOK') }}
          <select v-model="playbookId" class="block w-full rounded-md">
            <option :value="null">
              {{ $t('CAPTAIN.AGENTIC.SIMULATIONS.DEFAULT_PLAYBOOK') }}
            </option>
            <option
              v-for="playbook in eligiblePlaybooks"
              :key="playbook.id"
              :value="playbook.id"
            >
              {{ playbook.name }}
            </option>
          </select>
        </label>
        <label class="block text-sm">
          {{ $t('CAPTAIN.AGENTIC.SIMULATIONS.PROMPT') }}
          <textarea v-model="prompt" rows="3" class="block w-full rounded-md" />
        </label>
        <label class="block text-sm">
          {{ $t('CAPTAIN.AGENTIC.SIMULATIONS.MODEL') }}
          <input v-model="model" class="block w-full rounded-md" type="text" />
        </label>
        <div class="flex flex-wrap gap-3">
          <label class="block text-sm">
            {{ $t('CAPTAIN.AGENTIC.SIMULATIONS.LIMIT') }}
            <input
              v-model.number="limit"
              required
              class="block rounded-md"
              type="number"
              min="1"
              max="1000"
            />
          </label>
          <label class="block text-sm">
            {{ $t('CAPTAIN.AGENTIC.SIMULATIONS.INBOX') }}
            <input
              v-model.number="inboxId"
              class="block rounded-md"
              type="number"
              min="1"
            />
          </label>
        </div>
        <Button
          type="submit"
          :disabled="busy || !assistantId"
          :label="$t('CAPTAIN.AGENTIC.SIMULATIONS.CREATE')"
        />
      </form>
      <section class="space-y-3 rounded-lg border border-n-weak p-4">
        <div class="flex items-center justify-between">
          <h2 class="text-base font-semibold">
            {{ $t('CAPTAIN.AGENTIC.SIMULATIONS.RESULTS') }}
          </h2>
          <Button
            variant="outline"
            :disabled="busy"
            :label="$t('CAPTAIN.AGENTIC.REFRESH')"
            @click="selected ? show(selected.id, page) : load()"
          />
        </div>
        <p v-if="!runs.length && !busy" class="text-sm text-n-slate-11">
          {{ $t('CAPTAIN.AGENTIC.SIMULATIONS.NONE') }}
        </p>
        <button
          v-for="run in runs"
          :key="run.id"
          type="button"
          :disabled="busy"
          :aria-current="selected?.id === run.id ? 'true' : undefined"
          class="block w-full rounded-md border border-n-weak px-3 py-2 text-start text-sm"
          @click="show(run.id)"
        >
          {{
            $t('CAPTAIN.AGENTIC.SIMULATIONS.RUN', {
              id: run.id,
              status: run.status,
            })
          }}
        </button>
        <div v-if="selected" class="space-y-2">
          <p class="text-sm">
            {{
              $t('CAPTAIN.AGENTIC.SIMULATIONS.PROCESSED', {
                count: selected.processed_tickets,
              })
            }}
          </p>
          <pre
            v-if="Object.keys(selected.aggregate_metrics || {}).length"
            class="max-h-64 overflow-auto rounded-md bg-n-alpha-1 p-2 text-xs"
            >{{ JSON.stringify(selected.aggregate_metrics, null, 2) }}
          </pre>
          <article
            v-for="result in selected.results"
            :key="result.id"
            class="space-y-1 rounded-md border border-n-weak p-2 text-sm"
          >
            <h3 class="font-medium">
              {{
                $t('CAPTAIN.AGENTIC.SIMULATIONS.CONVERSATION', {
                  id: result.conversation_display_id,
                })
              }}
            </h3>
            <p class="whitespace-pre-wrap break-words">
              {{ result.simulated_response }}
            </p>
            <p v-if="result.judge_rationale" class="text-n-slate-11">
              {{ result.judge_rationale }}
            </p>
            <p class="text-n-slate-11">
              {{
                $t('CAPTAIN.AGENTIC.SIMULATIONS.SCORES', {
                  hallucination: result.hallucination_score,
                  policy: result.policy_adherence_score,
                })
              }}
            </p>
          </article>
          <div v-if="selected.result_count > pageSize" class="flex gap-2">
            <Button
              variant="outline"
              :disabled="busy || page === 1"
              :label="$t('CAPTAIN.AGENTIC.PREVIOUS')"
              @click="show(selected.id, page - 1)"
            />
            <Button
              variant="outline"
              :disabled="busy || page * pageSize >= selected.result_count"
              :label="$t('CAPTAIN.AGENTIC.NEXT')"
              @click="show(selected.id, page + 1)"
            />
          </div>
        </div>
      </section>
    </div>
  </main>
</template>
