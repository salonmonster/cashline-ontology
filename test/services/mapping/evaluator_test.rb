require "test_helper"

module Mapping
  class EvaluatorTest < ActiveSupport::TestCase
    test "rank_classes sums candidate scores per target class, descending" do
      lists = [
        [ { target_class: "Invoice", score: 0.9 }, { target_class: "Client::Contact", score: 0.2 } ],
        [ { target_class: "Invoice", score: 0.4 } ],
        [ { target_class: "Client::Contact", score: 0.1 } ]
      ]

      ranked = Evaluator.rank_classes(lists)

      assert_equal "Invoice", ranked.first.first
      assert_in_delta 1.3, ranked.first.last, 0.0001
      assert_equal %w[Invoice Client::Contact], ranked.map(&:first)
    end

    test "rank_classes tolerates empty candidate lists" do
      assert_empty Evaluator.rank_classes([ [], nil ])
    end
  end
end
