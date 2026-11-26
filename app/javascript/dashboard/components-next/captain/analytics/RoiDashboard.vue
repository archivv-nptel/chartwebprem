<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import Button from 'dashboard/components-next/button/Button.vue';
import RoiMetrics from 'dashboard/api/captain/roiMetrics';

const { accountId } = useAccount();
const { t, n } = useI18n();
const report = ref(null);
const loading = ref(false);
const failed = ref(false);
let request = 0;

const money = value => n(value, { style: 'currency', currency: 'USD' });
const rating = value => value ?? t('CAPTAIN.ROI.CSAT_UNAVAILABLE');

const metrics = computed(() => {
  if (!report.value) return [];
  const data = report.value;
  const {
    captain_ai_csat: aiCsat,
    human_agent_csat: humanCsat,
    delta,
  } = data.csat_parity;

  return [
    {
      key: 'VERIFIED',
      label: t('CAPTAIN.ROI.VERIFIED'),
      value: n(data.ai_verified_resolutions),
      detail: t('CAPTAIN.ROI.VERIFIED_DETAIL', {
        rate: n(data.deflection_rate_pct),
        total: n(data.total_verified_resolutions),
      }),
    },
    {
      key: 'SAVINGS',
      label: t('CAPTAIN.ROI.SAVINGS'),
      value: money(data.net_roi_savings_usd),
      detail: t('CAPTAIN.ROI.SAVINGS_DETAIL', {
        amount: money(data.gross_deflected_cost_usd),
      }),
    },
    {
      key: 'SPEND',
      label: t('CAPTAIN.ROI.SPEND'),
      value: money(data.captain_resolution_spend_usd),
    },
    {
      key: 'CSAT',
      label: t('CAPTAIN.ROI.CSAT'),
      value: `${rating(aiCsat)} / ${rating(humanCsat)}`,
      detail:
        delta == null
          ? t('CAPTAIN.ROI.CSAT_DETAIL')
          : t('CAPTAIN.ROI.CSAT_DELTA', { difference: n(delta) }),
    },
  ];
});

const load = async () => {
  request += 1;
  const currentRequest = request;
  report.value = null;
  failed.value = false;
  loading.value = true;
  try {
    const { data } = await RoiMetrics.get();
    if (currentRequest === request) report.value = data;
  } catch {
    if (currentRequest === request) failed.value = true;
  } finally {
    if (currentRequest === request) loading.value = false;
  }
};

watch(accountId, load, { immediate: true });
</script>

<template>
  <section class="flex flex-1 flex-col gap-6 overflow-y-auto p-6">
    <header class="flex flex-col gap-1">
      <h1 class="text-xl font-semibold text-n-slate-12">
        {{ t('CAPTAIN.ROI.TITLE') }}
      </h1>
      <p class="text-sm text-n-slate-11">{{ t('CAPTAIN.ROI.DESCRIPTION') }}</p>
    </header>
    <p v-if="loading" role="status" class="text-sm text-n-slate-11">
      {{ t('CAPTAIN.ROI.LOADING') }}
    </p>
    <div v-else-if="failed" class="flex items-center gap-3" role="alert">
      <p class="text-sm text-n-ruby-11">{{ t('CAPTAIN.ROI.ERROR') }}</p>
      <Button :label="t('CAPTAIN.ROI.RETRY')" sm faded @click="load" />
    </div>
    <dl v-else class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
      <div
        v-for="metric in metrics"
        :key="metric.key"
        class="rounded-xl border border-n-weak bg-n-solid-2 p-4"
      >
        <dt class="text-sm font-medium text-n-slate-11">
          {{ metric.label }}
        </dt>
        <dd class="mt-2 text-2xl font-semibold text-n-slate-12">
          {{ metric.value }}
        </dd>
        <dd v-if="metric.detail" class="mt-1 text-xs text-n-slate-11">
          {{ metric.detail }}
        </dd>
      </div>
    </dl>
  </section>
</template>
