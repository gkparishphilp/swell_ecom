module SwellEcom
	class WholesaleProfile < ApplicationRecord
		self.table_name = 'wholesale_profiles'

		has_many :wholesale_items

		enum status: { 'trash' => -1, 'draft' => 0, 'active' => 1, 'archived' => 2 }
		
		has_many_attached :embedded_attachments

		accepts_nested_attributes_for :wholesale_items

		def get_price( options )
			if ( item_polymorphic_id = options.delete(:item_polymorphic_id) ).present?
				options[:item_type], options[:item_id] = self.class.parse_polymorphic_id( item_polymorphic_id )
			end

			quantity = options.delete(:quantity) || 0

			WholesaleItem.unscoped.where( wholesale_profile: self ).where( options ).where( '? >= min_quantity', quantity ).order( min_quantity: :desc ).first.try(:price)
		end

		def items
			SwellEcom::Product.where( id: wholesale_items.where( item_type: SwellEcom::Product.name ).select(:item_id) )
		end

	end
end
