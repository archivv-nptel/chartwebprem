<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import Button from 'dashboard/components-next/button/Button.vue';
import KbProposalsAPI from 'dashboard/api/captain/kbProposals';

const { t } = useI18n();
const { accountId } = useAccount();
const proposals = ref([]);
const selected = ref(null);
const title = ref('');
const markdown = ref('');
const confirm = ref(null);
const error = ref('');
const busy = ref(false);
const page = ref(1);
const totalCount = ref(0);
const pageSize = 25;

async function request(callback, update) {
  const account = accountId.value;
  busy.value = true;
  error.value = '';
  try {
    const { data } = await callback();
    if (account === accountId.value) update(data);
  } catch (failure) {
    if (account === accountId.value) {
      error.value =
        failure.response?.status === 409
          ? t('CAPTAIN.AGENTIC.KNOWLEDGE.CONFLICT')
          : t('CAPTAIN.AGENTIC.REQUEST_ERROR');
    }
  } finally {
    if (account === accountId.value) busy.value = false;
  }
}

function select(proposal) {
  selected.value = proposal;
  title.value = proposal?.proposed_title || '';
  markdown.value = proposal?.proposed_markdown || '';
  confirm.value = null;
}

function updateProposal(proposal) {
  const index = proposals.value.findIndex(item => item.id === proposal.id);
  if (index !== -1) proposals.value.splice(index, 1, proposal);
  select(proposal);
}

function load(nextPage = 1) {
  return request(
    () => KbProposalsAPI.get(nextPage),
    data => {
      proposals.value = data.payload;
      totalCount.value = data.total_count;
      page.value = nextPage;
      select(null);
    }
  );
}

function show(proposal) {
  return request(() => KbProposalsAPI.show(proposal.id), updateProposal);
}

function save() {
  return request(
    () =>
      KbProposalsAPI.update(selected.value.id, {
        proposed_title: title.value.trim(),
        proposed_markdown: markdown.value,
      }),
    updateProposal
  );
}

async function decide(action) {
  if (confirm.value !== action) {
    confirm.value = action;
    return;
  }
  await request(
    () => KbProposalsAPI[action](selected.value.id),
    updateProposal
  );
}

watch(
  accountId,
  () => {
    proposals.value = [];
    select(null);
    load();
  },
  { immediate: true }
);
</script>

<template>
  <main class="h-full w-full overflow-y-auto px-4 py-6">
    <div class="mx-auto max-w-5xl space-y-4">
      <h1 class="text-xl font-semibold">
        {{ $t('CAPTAIN.AGENTIC.NAV.KNOWLEDGE') }}
      </h1>
      <p class="text-sm text-n-slate-11">
        {{ $t('CAPTAIN.AGENTIC.KNOWLEDGE.DESCRIPTION') }}
      </p>
      <p v-if="error" role="alert" class="text-sm text-n-ruby-11">
        {{ error }}
      </p>
      <div class="grid gap-4 md:grid-cols-[14rem_1fr]">
        <aside class="space-y-2">
          <Button
            variant="outline"
            :disabled="busy"
            :label="$t('CAPTAIN.AGENTIC.REFRESH')"
            @click="load(page)"
          />
          <p v-if="!proposals.length && !busy" class="text-sm text-n-slate-11">
            {{ $t('CAPTAIN.AGENTIC.KNOWLEDGE.NONE') }}
          </p>
          <button
            v-for="proposal in proposals"
            :key="proposal.id"
            type="button"
            :disabled="busy"
            :aria-current="selected?.id === proposal.id ? 'true' : undefined"
            class="block w-full rounded-md border border-n-weak p-2 text-start text-sm"
            @click="show(proposal)"
          >
            <span>{{ proposal.proposed_title }}</span>
            <span class="block text-xs text-n-slate-11">{{
              proposal.status
            }}</span>
          </button>
          <div v-if="totalCount > pageSize" class="flex flex-wrap gap-2">
            <Button
              variant="outline"
              :disabled="busy || page === 1"
              :label="$t('CAPTAIN.AGENTIC.PREVIOUS')"
              @click="load(page - 1)"
            />
            <Button
              variant="outline"
              :disabled="busy || page * pageSize >= totalCount"
              :label="$t('CAPTAIN.AGENTIC.NEXT')"
              @click="load(page + 1)"
            />
          </div>
        </aside>
        <form
          v-if="selected"
          class="min-w-0 space-y-3 rounded-lg border border-n-weak p-4"
          @submit.prevent="save"
        >
          <p class="text-sm">
            {{ $t('CAPTAIN.AGENTIC.STATUS', { status: selected.status }) }}
          </p>
          <label class="block text-sm">
            {{ $t('CAPTAIN.AGENTIC.KNOWLEDGE.TITLE') }}
            <input
              v-model="title"
              required
              :disabled="selected.status !== 'open'"
              class="block w-full rounded-md"
            />
          </label>
          <label class="block text-sm">
            {{ $t('CAPTAIN.AGENTIC.KNOWLEDGE.BODY') }}
            <textarea
              v-model="markdown"
              required
              :disabled="selected.status !== 'open'"
              rows="8"
              class="block w-full rounded-md font-mono text-xs"
            />
          </label>
          <div v-if="selected.unified_diff">
            <h2 class="text-sm font-medium">
              {{ $t('CAPTAIN.AGENTIC.KNOWLEDGE.DIFF') }}
            </h2>
            <pre
              class="max-h-96 overflow-auto rounded-md bg-n-alpha-1 p-2 text-xs"
              >{{ selected.unified_diff }}
            </pre>
          </div>
          <div v-if="selected.status === 'open'" class="flex flex-wrap gap-2">
            <Button
              type="submit"
              :disabled="busy"
              :label="$t('CAPTAIN.AGENTIC.SAVE')"
            />
            <Button
              type="button"
              variant="outline"
              :disabled="
                busy ||
                title !== selected.proposed_title ||
                markdown !== selected.proposed_markdown
              "
              :label="
                confirm === 'merge'
                  ? $t('CAPTAIN.AGENTIC.KNOWLEDGE.CONFIRM_MERGE')
                  : $t('CAPTAIN.AGENTIC.KNOWLEDGE.MERGE')
              "
              @click="decide('merge')"
            />
            <Button
              type="button"
              color="ruby"
              variant="outline"
              :disabled="busy"
              :label="
                confirm === 'reject'
                  ? $t('CAPTAIN.AGENTIC.KNOWLEDGE.CONFIRM_REJECT')
                  : $t('CAPTAIN.AGENTIC.KNOWLEDGE.REJECT')
              "
              @click="decide('reject')"
            />
          </div>
        </form>
      </div>
    </div>
  </main>
</template>
