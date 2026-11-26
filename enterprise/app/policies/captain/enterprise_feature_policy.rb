class Captain::EnterpriseFeaturePolicy < ApplicationPolicy
  def permitted?(feature_name, require_admin: false)
    return false unless account && account_user && account.feature_enabled?(feature_name)

    account_user.administrator? || (!require_admin && account_user.agent?)
  end
end
