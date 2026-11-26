class Captain::Knowledge::ScheduleGapDetectionJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.feature_captain_self_healing_kb.where(id: Portal.active.select(:account_id)).find_each do |account|
      delay = (account.id % 720).minutes
      Captain::Knowledge::GapDetectorJob.set(wait: delay).perform_later(account.id)
    end
  end
end
