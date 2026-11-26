class Captain::Metering::RoiAggregatorService
  pattr_initialize [:account!, :from!, :to!]

  def summary
    totals = grouped_totals
    ai_count, gross, fees, ai_csat = totals.fetch('captain_ai', [0, 0, 0, nil])
    human_csat = totals.dig('human_agent', 3)
    total = totals.values.sum(&:first)

    {
      period: { from: from.iso8601, to: to.iso8601 },
      total_verified_resolutions: total,
      ai_verified_resolutions: ai_count,
      deflection_rate_pct: total.zero? ? 0 : (ai_count.fdiv(total) * 100).round(2),
      gross_deflected_cost_usd: gross.to_f.round(2),
      captain_resolution_spend_usd: fees.to_f.round(2),
      net_roi_savings_usd: (gross - fees).to_f.round(2),
      csat_parity: csat_parity(ai_csat, human_csat)
    }
  end

  private

  def grouped_totals
    attributes = Captain::ResolutionEvent.arel_table
    account.captain_resolution_events.verified.where(resolved_at: from..to).group(:resolution_actor)
           .pluck(:resolution_actor, attributes[:id].count, attributes[:estimated_human_cost_usd].sum, attributes[:billable_fee_usd].sum,
                  attributes[:csat_rating].average)
           .to_h { |actor, *metrics| [actor, metrics] }
  end

  def csat_parity(ai_csat, human_csat)
    {
      captain_ai_csat: ai_csat&.to_f&.round(2),
      human_agent_csat: human_csat&.to_f&.round(2),
      delta: ai_csat && human_csat ? (ai_csat - human_csat).to_f.round(2) : nil
    }
  end
end
