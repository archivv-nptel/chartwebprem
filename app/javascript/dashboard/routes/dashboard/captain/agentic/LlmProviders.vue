<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import Button from 'dashboard/components-next/button/Button.vue';
import LlmProvidersAPI from 'dashboard/api/captain/llmProviders';

const { t } = useI18n();
const { accountId } = useAccount();

const providerTypes = computed(() => ({
  openai_compatible: t('CAPTAIN.AGENTIC.PROVIDERS.TYPES.OPENAI_COMPATIBLE'),
  aws_bedrock: t('CAPTAIN.AGENTIC.PROVIDERS.TYPES.AWS_BEDROCK'),
  azure_openai: t('CAPTAIN.AGENTIC.PROVIDERS.TYPES.AZURE_OPENAI'),
  google_vertex: t('CAPTAIN.AGENTIC.PROVIDERS.TYPES.GOOGLE_VERTEX'),
}));
const credentialHelp = computed(() => ({
  openai_compatible: t('CAPTAIN.AGENTIC.PROVIDERS.KEYS.OPENAI_COMPATIBLE'),
  aws_bedrock: t('CAPTAIN.AGENTIC.PROVIDERS.KEYS.AWS_BEDROCK'),
  azure_openai: t('CAPTAIN.AGENTIC.PROVIDERS.KEYS.AZURE_OPENAI'),
  google_vertex: t('CAPTAIN.AGENTIC.PROVIDERS.KEYS.GOOGLE_VERTEX'),
}));
const defaultProvider = () => ({
  name: '',
  provider_type: 'openai_compatible',
  model_id: '',
  endpoint_url: '',
  region: '',
  priority: 100,
  enabled: true,
  zero_data_retention: false,
});

const providers = ref([]);
const selectedId = ref(null);
const form = ref(defaultProvider());
const credentials = ref('');
const routingRules = ref('{}');
const busy = ref(false);
const showRemove = ref(false);
const error = ref('');
const notice = ref('');
const needsRegion = computed(() =>
  ['aws_bedrock', 'google_vertex'].includes(form.value.provider_type)
);

async function runRequest(
  request,
  onSuccess,
  failure = t('CAPTAIN.AGENTIC.REQUEST_ERROR')
) {
  const account = accountId.value;
  busy.value = true;
  error.value = '';
  notice.value = '';
  try {
    const { data } = await request();
    if (account === accountId.value) onSuccess(data);
  } catch {
    if (account === accountId.value) error.value = failure;
  } finally {
    if (account === accountId.value) busy.value = false;
  }
}

function open(provider) {
  selectedId.value = provider?.id ?? null;
  form.value = Object.fromEntries(
    Object.entries(defaultProvider()).map(([key, value]) => [
      key,
      provider?.[key] ?? value,
    ])
  );
  credentials.value = '';
  routingRules.value = JSON.stringify(provider?.routing_rules || {}, null, 2);
  showRemove.value = false;
  error.value = '';
  notice.value = '';
}

function parseObject(input) {
  const value = JSON.parse(input);
  if (!value || Array.isArray(value) || typeof value !== 'object') {
    throw new TypeError();
  }
  return value;
}

async function save() {
  let payload;
  try {
    payload = {
      ...form.value,
      endpoint_url: needsRegion.value ? null : form.value.endpoint_url.trim(),
      region: needsRegion.value ? form.value.region.trim() : null,
      routing_rules: parseObject(routingRules.value),
    };
    if (credentials.value.trim())
      payload.credentials = parseObject(credentials.value);
  } catch {
    error.value = t('CAPTAIN.AGENTIC.INVALID_JSON');
    return;
  }
  await runRequest(
    () =>
      selectedId.value
        ? LlmProvidersAPI.update(selectedId.value, payload)
        : LlmProvidersAPI.create(payload),
    provider => {
      const index = providers.value.findIndex(item => item.id === provider.id);
      if (index < 0) providers.value.push(provider);
      else providers.value.splice(index, 1, provider);
      open(provider);
      notice.value = t('CAPTAIN.AGENTIC.PROVIDERS.SAVED');
    }
  );
}

function testConnection() {
  return runRequest(
    () => LlmProvidersAPI.testConnection(selectedId.value),
    data => {
      if (data?.success === false || data?.ok === false) {
        error.value = t('CAPTAIN.AGENTIC.PROVIDERS.TEST_ERROR');
      } else {
        notice.value = t('CAPTAIN.AGENTIC.PROVIDERS.TESTED');
      }
    },
    t('CAPTAIN.AGENTIC.PROVIDERS.TEST_ERROR')
  );
}

function remove() {
  const id = selectedId.value;
  return runRequest(
    () => LlmProvidersAPI.delete(id),
    () => {
      providers.value = providers.value.filter(provider => provider.id !== id);
      open();
    }
  );
}

watch(
  accountId,
  () => {
    open();
    providers.value = [];
    runRequest(
      () => LlmProvidersAPI.get(),
      data => {
        providers.value = data.payload;
      },
      t('CAPTAIN.AGENTIC.LOAD_ERROR')
    );
  },
  { immediate: true }
);
</script>

<template>
  <main class="h-full w-full overflow-y-auto px-4 py-6">
    <div class="mx-auto max-w-5xl space-y-4">
      <h1 class="text-xl font-semibold text-n-slate-12">
        {{ $t('CAPTAIN.AGENTIC.NAV.PROVIDERS') }}
      </h1>
      <p class="text-sm text-n-slate-11">
        {{ $t('CAPTAIN.AGENTIC.PROVIDERS.DESCRIPTION') }}
      </p>
      <div class="grid gap-4 md:grid-cols-[14rem_1fr]">
        <aside class="space-y-2">
          <Button
            variant="outline"
            :disabled="busy"
            :label="$t('CAPTAIN.AGENTIC.PROVIDERS.NEW')"
            @click="open()"
          />
          <button
            v-for="provider in providers"
            :key="provider.id"
            type="button"
            :disabled="busy"
            :aria-current="selectedId === provider.id ? 'true' : undefined"
            class="block w-full rounded-md border border-n-weak p-2 text-start text-sm"
            @click="open(provider)"
          >
            <span>{{ provider.name }}</span>
            <span class="block text-xs text-n-slate-11">{{
              provider.model_id
            }}</span>
          </button>
        </aside>
        <form
          class="min-w-0 space-y-3 rounded-lg border border-n-weak p-4"
          @submit.prevent="save"
        >
          <label class="block text-sm">
            {{ $t('CAPTAIN.AGENTIC.NAME') }}
            <input
              v-model="form.name"
              type="text"
              required
              class="block w-full rounded-md"
            />
          </label>
          <label class="block text-sm">
            {{ $t('CAPTAIN.AGENTIC.PROVIDERS.TYPE') }}
            <select
              v-model="form.provider_type"
              class="block w-full rounded-md"
              :disabled="!!selectedId"
            >
              <option
                v-for="(label, type) in providerTypes"
                :key="type"
                :value="type"
              >
                {{ label }}
              </option>
            </select>
          </label>
          <label class="block text-sm">
            {{ $t('CAPTAIN.AGENTIC.PROVIDERS.MODEL') }}
            <input
              v-model="form.model_id"
              type="text"
              required
              class="block w-full rounded-md"
            />
          </label>
          <label v-if="needsRegion" class="block text-sm">
            {{ $t('CAPTAIN.AGENTIC.PROVIDERS.REGION') }}
            <input
              v-model="form.region"
              type="text"
              required
              class="block w-full rounded-md"
            />
          </label>
          <label v-else class="block text-sm">
            {{ $t('CAPTAIN.AGENTIC.PROVIDERS.ENDPOINT') }}
            <input
              v-model="form.endpoint_url"
              type="url"
              required
              class="block w-full rounded-md"
            />
          </label>
          <label class="block text-sm">
            {{ $t('CAPTAIN.AGENTIC.PROVIDERS.PRIORITY') }}
            <input
              v-model.number="form.priority"
              type="number"
              min="1"
              max="1000"
              required
              class="block rounded-md"
            />
          </label>
          <label class="flex items-center gap-2 text-sm">
            <input v-model="form.enabled" type="checkbox" />
            {{ $t('CAPTAIN.AGENTIC.PROVIDERS.ENABLED') }}
          </label>
          <label class="flex items-center gap-2 text-sm">
            <input v-model="form.zero_data_retention" type="checkbox" />
            {{ $t('CAPTAIN.AGENTIC.PROVIDERS.ZERO_RETENTION') }}
          </label>
          <label class="block text-sm">
            {{ $t('CAPTAIN.AGENTIC.PROVIDERS.CREDENTIALS') }}
            <textarea
              v-model="credentials"
              rows="3"
              spellcheck="false"
              autocomplete="off"
              class="block w-full rounded-md font-mono text-xs"
            />
            <span class="text-xs text-n-slate-11">{{
              credentialHelp[form.provider_type]
            }}</span>
            <span v-if="selectedId" class="block text-xs text-n-slate-11">{{
              $t('CAPTAIN.AGENTIC.PROVIDERS.KEEP_CREDENTIALS')
            }}</span>
          </label>
          <label class="block text-sm">
            {{ $t('CAPTAIN.AGENTIC.PROVIDERS.ROUTING') }}
            <textarea
              v-model="routingRules"
              rows="3"
              spellcheck="false"
              class="block w-full rounded-md font-mono text-xs"
            />
          </label>
          <p v-if="error" role="alert" class="text-sm text-n-ruby-11">
            {{ error }}
          </p>
          <p v-if="notice" role="status" class="text-sm text-n-teal-11">
            {{ notice }}
          </p>
          <div class="flex flex-wrap gap-2">
            <Button
              type="submit"
              :disabled="busy"
              :label="$t('CAPTAIN.AGENTIC.SAVE')"
            />
            <template v-if="selectedId">
              <Button
                type="button"
                variant="outline"
                :disabled="busy"
                :label="$t('CAPTAIN.AGENTIC.PROVIDERS.TEST')"
                @click="testConnection"
              />
              <Button
                type="button"
                color="ruby"
                variant="outline"
                :disabled="busy"
                :label="
                  showRemove
                    ? $t('CAPTAIN.AGENTIC.CONFIRM_REMOVE')
                    : $t('CAPTAIN.AGENTIC.REMOVE')
                "
                @click="showRemove ? remove() : (showRemove = true)"
              />
            </template>
          </div>
        </form>
      </div>
    </div>
  </main>
</template>
