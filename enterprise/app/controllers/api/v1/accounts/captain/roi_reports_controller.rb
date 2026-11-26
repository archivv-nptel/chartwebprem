class Api::V1::Accounts::Captain::RoiReportsController < Api::V1::Accounts::Captain::AgenticBaseController
  before_action { authorize_captain_feature!(:captain_outcome_metering, require_admin: true) }

  def show
    from = parse_boundary(:from, 30.days.ago)
    to = parse_boundary(:to, Time.current)
    return invalid_period if from > to || (to - from) > 366.days

    render json: ::Captain::Metering::RoiAggregatorService.new(account: Current.account, from: from, to: to).summary
  rescue ArgumentError
    invalid_period
  end

  private

  def parse_boundary(key, default)
    value = params[key]
    return default if value.nil?
    raise ArgumentError unless value.is_a?(String)

    Time.zone.iso8601(value)
  end

  def invalid_period
    render json: { error: I18n.t('captain.outcomes.invalid_period') }, status: :unprocessable_entity
  end
end
