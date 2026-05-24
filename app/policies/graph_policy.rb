class GraphPolicy < Struct.new(:user, :record)
  def show?
    user.present?
  end
end
