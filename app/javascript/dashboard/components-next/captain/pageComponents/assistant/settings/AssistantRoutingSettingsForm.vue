<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { usePolicy } from 'dashboard/composables/usePolicy';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import LlmProvidersAPI from 'dashboard/api/captain/llmProviders';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  assistant: { type: Object, required: true },
});
const emit = defineEmits(['submit']);
const { accountId } = useAccount();
const { isFeatureFlagEnabled } = usePolicy();
const { t } = useI18n();

const llmEnabled = computed(() =>
  isFeatureFlagEnabled(FEATURE_FLAGS.CAPTAIN_BYOM_ROUTING)
);
const swarmEnabled = computed(() =>
  isFeatureFlagEnabled(FEATURE_FLAGS.CAPTAIN_SWARM_HANDOFFS)
);
const providerId = ref(null);
const swarmRole = ref('');
const capabilities = ref('');
const providers = ref([]);
const loadError = ref('');
const loading = ref(false);

watch(
  () => props.assistant,
  assistant => {
    providerId.value = assistant.llm_provider_config_id ?? null;
    swarmRole.value = assistant.swarm_role || '';
    capabilities.value = assistant.swarm_capabilities?.join(', ') || '';
  },
  { immediate: true }
);

watch(
  [accountId, llmEnabled],
  async ([account, enabled]) => {
    providers.value = [];
    loadError.value = '';
    loading.value = enabled;
    if (!enabled) return;
    try {
      const { data } = await LlmProvidersAPI.get();
      if (account === accountId.value) providers.value = data.payload;
    } catch {
      if (account === accountId.value)
        loadError.value = t('CAPTAIN.AGENTIC.LOAD_ERROR');
    } finally {
      if (account === accountId.value) loading.value = false;
    }
  },
  { immediate: true }
);

function save() {
  const assistant = {};
  if (llmEnabled.value) assistant.llm_provider_config_id = providerId.value;
  if (swarmEnabled.value) {
    assistant.swarm_role = swarmRole.value.trim() || null;
    assistant.swarm_capabilities = capabilities.value
      .split(',')
      .map(value => value.trim())
      .filter(Boolean);
  }
  emit('submit', { assistant });
}
</script>

<template>
  <form
    v-show="llmEnabled || swarmEnabled"
    class="space-y-3 border-t border-n-weak pt-4"
    @submit.prevent="save"
  >
    <h2 class="text-base font-medium">
      {{ $t('CAPTAIN.AGENTIC.ROUTING.TITLE') }}
    </h2>
    <label v-if="llmEnabled" class="block text-sm">
      {{ $t('CAPTAIN.AGENTIC.ROUTING.PROVIDER') }}
      <select
        v-model="providerId"
        class="block w-full rounded-md"
        :disabled="loading"
      >
        <option :value="null">
          {{ $t('CAPTAIN.AGENTIC.ROUTING.DEFAULT_PROVIDER') }}
        </option>
        <option
          v-for="provider in providers"
          :key="provider.id"
          :value="provider.id"
        >
          {{ provider.name }}
        </option>
      </select>
    </label>
    <template v-if="swarmEnabled">
      <label class="block text-sm">
        {{ $t('CAPTAIN.AGENTIC.ROUTING.ROLE') }}
        <input
          v-model="swarmRole"
          type="text"
          class="block w-full rounded-md"
        />
      </label>
      <label class="block text-sm">
        {{ $t('CAPTAIN.AGENTIC.ROUTING.CAPABILITIES') }}
        <input
          v-model="capabilities"
          type="text"
          class="block w-full rounded-md"
        />
      </label>
    </template>
    <p v-if="loadError" role="alert" class="text-sm text-n-ruby-11">
      {{ loadError }}
    </p>
    <Button
      type="submit"
      :disabled="loading || !!loadError"
      :label="$t('CAPTAIN.AGENTIC.SAVE')"
    />
  </form>
</template>
