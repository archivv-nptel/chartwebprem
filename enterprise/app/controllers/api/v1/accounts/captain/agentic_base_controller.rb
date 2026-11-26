class Api::V1::Accounts::Captain::AgenticBaseController < Api::V1::Accounts::BaseController
  private

  def authorize_captain_feature!(feature, require_admin: false)
    policy = ::Captain::EnterpriseFeaturePolicy.new(pundit_user, Current.account)
    head :forbidden unless policy.permitted?(feature, require_admin: require_admin)
  end
end
