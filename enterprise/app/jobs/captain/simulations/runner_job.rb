class Captain::Simulations::RunnerJob < ApplicationJob
  queue_as :low

  BATCH_SIZE = 10

  def perform(run_id, offset = 0)
    run = Captain::SimulationRun.find_by(id: run_id)
    return if run.blank? || !prepare(run, offset)

    process_batch(run, offset)
    complete_or_continue(run)
  end

  private

  def prepare(run, offset)
    run.with_lock do
      return false if run.completed? || run.failed?
      return false unless run.processed_tickets.between?(offset, offset + BATCH_SIZE)

      unless run.account.feature_enabled?(:captain_simulations)
        mark_failed!(run, 'feature_disabled')
        return false
      end

      if run.queued?
        ticket_ids = run.ticket_scope.ids
        run.update!(status: :running, ticket_ids: ticket_ids, total_tickets: ticket_ids.length, started_at: Time.current)
      end
    end
    true
  end

  def process_batch(run, offset)
    evaluator = Captain::Simulations::EvaluatorService.new(run)
    end_index = [offset + BATCH_SIZE, run.total_tickets].min
    (run.processed_tickets...end_index).each do |index|
      conversation = run.account.conversations.find_by(id: run.ticket_ids.fetch(index))
      attributes = evaluator.evaluate(conversation)

      run.with_lock do
        next unless run.running? && run.processed_tickets == index

        run.results.create!(conversation: conversation, **attributes) if attributes
        run.update!(processed_tickets: index + 1)
      end
    end
  rescue StandardError
    run.with_lock { mark_failed!(run, 'evaluation_failed') if run.running? }
    raise
  end

  def complete_or_continue(run)
    next_offset = run.with_lock do
      return unless run.running?

      if run.processed_tickets == run.total_tickets
        run.update!(status: :completed, completed_at: Time.current, aggregate_metrics: metrics(run))
        return
      end

      run.processed_tickets
    end
    self.class.perform_later(run.id, next_offset)
  end

  def metrics(run)
    results = run.results
    evaluated = results.count
    {
      projected_deflection_rate: evaluated.positive? ? (results.where(projected_deflection: true).count.to_f / evaluated).round(4) : nil,
      avg_hallucination_score: results.average(:hallucination_score)&.round(4),
      avg_policy_adherence: results.average(:policy_adherence_score)&.round(4),
      evaluated_tickets: evaluated,
      skipped_tickets: run.total_tickets - evaluated
    }
  end

  def mark_failed!(run, code)
    run.update!(status: :failed, aggregate_metrics: { error: code }, completed_at: Time.current)
  end
end
