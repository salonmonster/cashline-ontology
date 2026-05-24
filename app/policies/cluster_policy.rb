class ClusterPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    user.present?
  end

  def edit?
    user.present? && (user.analyst? || user.admin?)
  end

  alias_method :rename?, :edit?
  alias_method :assign?, :edit?
  alias_method :reset?, :edit?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none if user.nil?
      scope
    end
  end
end
