module SwellEcom
	class Discount < ActiveRecord::Base
		self.table_name = 'discounts'

		has_many :discount_items
		has_many :discount_users

		enum status: { 'archived' => -1, 'draft' => 0, 'active' => 1 }
		enum availability: { 'anyone' => 1, 'selected_users' => 2 }
		enum duration: { 'one_charge_only' => 1, 'amount_of_charges' => 2, 'all_charges' => 2 }

		def in_progress?( args = {} )
			args[:now] ||= Time.now

			( start_at.nil? || args[:now] > start_at ) && ( end_at.nil? || args[:now] < end_at )
		end

		def self.in_progress( args = {} )

			args[:now] ||= Time.now

			self.where('( start_at IS NULL OR :now > start_at ) AND ( end_at IS NULL OR :now < end_at )', now: args[:now] )

		end

	end
end
