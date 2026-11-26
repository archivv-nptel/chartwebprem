<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { useCaptainAgenticStore } from 'dashboard/store/captain/agenticStore';

const props = defineProps({
  approval: { type: Object, required: true },
});

const { t } = useI18n();
const store = useCaptainAgenticStore();
const editedArguments = ref('');
const originalArguments = ref('');
const reason = ref('');
const showReject = ref(false);
const busy = ref(false);
const error = ref('');

watch(
  () => props.approval.id,
  () => {
    originalArguments.value = JSON.stringify(
      props.approval.proposed_arguments,
      null,
      2
    );
    editedArguments.value = originalArguments.value;
  },
  { immediate: true }
);

async function approve() {
  error.value = '';
  let args;
  try {
    if (editedArguments.value !== originalArguments.value) {
      args = JSON.parse(editedArguments.value);
      if (!args || Array.isArray(args) || typeof args !== 'object') {
        throw new TypeError();
      }
    }
  } catch {
    error.value = t('CAPTAIN.AGENTIC.INVALID_JSON');
    return;
  }

  busy.value = true;
  try {
    await store.approveAction(props.approval.id, args);
  } catch {
    error.value = t('CAPTAIN.AGENTIC.APPROVALS.DECISION_ERROR');
  } finally {
    busy.value = false;
  }
}

async function reject() {
  busy.value = true;
  error.value = '';
  try {
    await store.rejectAction(props.approval.id, reason.value);
    showReject.value = false;
  } catch {
    error.value = t('CAPTAIN.AGENTIC.APPROVALS.DECISION_ERROR');
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <article
    class="space-y-2 rounded-lg border border-n-amber-6 bg-n-amber-2 p-3"
  >
    <h3 class="text-sm font-semibold text-n-slate-12">
      {{
        $t('CAPTAIN.AGENTIC.APPROVALS.REQUEST', { tool: approval.tool_name })
      }}
    </h3>
    <p v-if="approval.risk_level" class="text-xs font-medium text-n-amber-11">
      {{ $t('CAPTAIN.AGENTIC.APPROVALS.RISK', { level: approval.risk_level }) }}
    </p>
    <p v-if="approval.rationale" class="text-sm text-n-slate-11">
      {{ approval.rationale }}
    </p>
    <label v-if="approval.status === 'pending'" class="block text-sm">
      {{ $t('CAPTAIN.AGENTIC.APPROVALS.ARGUMENTS') }}
      <textarea
        v-model="editedArguments"
        rows="3"
        :disabled="busy"
        class="w-full rounded-md border border-n-weak bg-n-solid-1 p-2 font-mono text-xs"
      />
    </label>
    <div v-if="approval.status === 'pending'" class="flex flex-wrap gap-2">
      <Button
        size="sm"
        :disabled="busy"
        :label="$t('CAPTAIN.AGENTIC.APPROVALS.APPROVE')"
        @click="approve"
      />
      <Button
        size="sm"
        variant="outline"
        color="ruby"
        :disabled="busy"
        :label="$t('CAPTAIN.AGENTIC.APPROVALS.REJECT')"
        @click="showReject = !showReject"
      />
    </div>
    <p v-else class="text-sm text-n-slate-11">
      {{ $t('CAPTAIN.AGENTIC.STATUS', { status: approval.status }) }}
    </p>
    <div
      v-if="showReject && approval.status === 'pending'"
      class="flex flex-wrap items-end gap-2"
    >
      <label class="block grow text-sm">
        {{ $t('CAPTAIN.AGENTIC.APPROVALS.REASON') }}
        <input
          v-model="reason"
          class="w-full rounded-md border border-n-weak bg-n-solid-1"
          maxlength="1000"
          :disabled="busy"
        />
      </label>
      <Button
        size="sm"
        color="ruby"
        :disabled="busy"
        :label="$t('CAPTAIN.AGENTIC.APPROVALS.CONFIRM_REJECT')"
        @click="reject"
      />
    </div>
    <p v-if="error" role="alert" class="text-sm text-n-ruby-11">{{ error }}</p>
  </article>
</template>
