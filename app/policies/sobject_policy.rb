class SobjectPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    return false if user.nil?
    return true unless record.extraction_run&.include_sensitive
    user.sensitive_data_access?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none if user.nil?
      scope
    end
  end
end
