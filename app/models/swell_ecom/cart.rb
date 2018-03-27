module SwellEcom
	class Cart < ApplicationRecord
		self.table_name = 'carts'

		enum status: { 'active' => 1, 'init_checkout' => 2, 'success' => 3 }

		has_many :cart_items, dependent: :destroy

		belongs_to :order, required: false

	end
end
