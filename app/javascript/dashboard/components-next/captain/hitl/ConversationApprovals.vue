<script setup>
import { computed, onMounted, onUnmounted, ref, watch } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { usePolicy } from 'dashboard/composables/usePolicy';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import {
  CONVERSATION_PERMISSIONS,
  ROLES,
} from 'dashboard/constants/permissions';
import { INSTALLATION_TYPES } from 'dashboard/constants/installationTypes';
import { useCaptainAgenticStore } from 'dashboard/store/captain/agenticStore';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { emitter } from 'shared/helpers/mitt';
import HitlApprovalCard from './HitlApprovalCard.vue';

const props = defineProps({
  conversationId: { type: Number, required: true },
});
const { accountId } = useAccount();
const { isFeatureFlagEnabled, checkPermissions, checkInstallationType } =
  usePolicy();
const store = useCaptainAgenticStore();
const failed = ref(false);

const active = computed(
  () =>
    isFeatureFlagEnabled(FEATURE_FLAGS.CAPTAIN_HITL_APPROVALS) &&
    checkInstallationType([
      INSTALLATION_TYPES.CLOUD,
      INSTALLATION_TYPES.ENTERPRISE,
    ]) &&
    checkPermissions([...ROLES, ...CONVERSATION_PERMISSIONS])
);
const visibleApprovals = computed(() =>
  store.approvals.filter(
    approval =>
      approval.status === 'pending' || store.reviewedIds.includes(approval.id)
  )
);

async function refresh() {
  failed.value = false;
  if (!active.value) return;
  const account = accountId.value;
  const conversation = props.conversationId;
  try {
    await store.fetchApprovals(account, conversation);
  } catch (error) {
    if (account === accountId.value && conversation === props.conversationId) {
      failed.value = ![403, 404].includes(error.response?.status);
    }
  }
}

function onApprovalEvent(data) {
  if (
    data.account_id === accountId.value &&
    data.conversation_display_id === props.conversationId
  ) {
    refresh();
  }
}

watch(
  [active, accountId, () => props.conversationId],
  () => {
    store.clearApprovals();
    refresh();
  },
  { immediate: true }
);

onMounted(() => {
  emitter.on(BUS_EVENTS.CAPTAIN_APPROVAL_CHANGED, onApprovalEvent);
  emitter.on(BUS_EVENTS.WEBSOCKET_RECONNECT, refresh);
});

onUnmounted(() => {
  emitter.off(BUS_EVENTS.CAPTAIN_APPROVAL_CHANGED, onApprovalEvent);
  emitter.off(BUS_EVENTS.WEBSOCKET_RECONNECT, refresh);
  store.clearApprovals();
});
</script>

<template>
  <div>
    <section
      v-if="active && (visibleApprovals.length || failed)"
      class="max-h-64 shrink-0 space-y-2 overflow-y-auto px-4 py-2"
      :aria-label="$t('CAPTAIN.AGENTIC.APPROVALS.TITLE')"
    >
      <HitlApprovalCard
        v-for="approval in visibleApprovals"
        :key="approval.id"
        :approval="approval"
      />
      <button v-if="failed" class="text-sm text-n-ruby-11" @click="refresh">
        {{ $t('CAPTAIN.AGENTIC.APPROVALS.RETRY') }}
      </button>
    </section>
  </div>
</template>
