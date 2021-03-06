module SwellEcom

	class OrderService < ::ApplicationService
		# abstract

		def initialize( args = {} )

			@fraud_service		= args[:fraud_service]
			@fraud_service		||= SwellEcom.fraud_service_class.constantize.new( SwellEcom.fraud_service_config )

			@shipping_service		= args[:shipping_service]
			@shipping_service		||= SwellEcom.shipping_service_class.constantize.new( SwellEcom.shipping_service_config )

			@tax_service			= args[:tax_service]
			@tax_service			||= SwellEcom.tax_service_class.constantize.new( SwellEcom.tax_service_config )

			@transaction_service	= args[:transaction_service]
			@transaction_service	||= SwellEcom.transaction_service_class.constantize.new( SwellEcom.transaction_service_config )

			@discount_service		= args[:discount_service]
			@discount_service		||= SwellEcom.discount_service_class.constantize.new( SwellEcom.discount_service_config )

			@subscription_service = args[:subscription_service]
			@subscription_service		||= SwellEcom.subscription_service_class.constantize.new( SwellEcom.subscription_service_config.merge( order_service: self ) )

		end

		def calculate( obj, args = {} )

			args[:discount] ||= {}
			args[:shipping] ||= {}
			args[:tax] ||= {}
			args[:transaction] ||= {}

			self.calculate_order_before( obj, args ) if obj.is_a? SwellEcom::Order

			shipping_response					= @shipping_service.calculate( obj, args[:shipping] )
			discount_pretax_response	= @discount_service.calculate( obj, args[:discount].merge( pre_tax: true ) ) # calculate discounts pre-tax
			tax_response							= @tax_service.calculate( obj, args[:tax] )
			discount_response					= @discount_service.calculate( obj, args[:discount] ) # calucate again after taxes
			transaction_response			= @transaction_service.calculate( obj, args[:transaction] )

			self.calculate_order_after( obj, args ) if obj.is_a? SwellEcom::Order

			{
				shipping: shipping_response,
				discount_pretax: discount_pretax_response,
				discount: discount_response,
				tax: tax_response,
				transaction: transaction_response,
			}
		end

		def discount_service
			@discount_service
		end

		def fraud_service
			@fraud_service
		end

		def process( order, args = {} )

			args[:discount] ||= {}
			args[:shipping] ||= {}
			args[:tax] ||= {}
			args[:transaction] ||= {}

			self.calculate( order, args )
			return nil unless self.validate( order, args )

			return self.process_capture_payment_method( order, args ) if order.pre_order?
			return self.process_purchase( order, args ) if order.active?
			raise Exception.new( 'OrderService#process: invalid order status' )
		end

		def process_purchase( order, args = {} )

			if order.total == 0
				@transaction_service.capture_payment_method( order, args[:transaction] ) unless order.parent.is_a? SwellEcom::Subscription

				if order.nested_errors.blank?
					order.payment_status = 'paid'
					order.status = 'active'
					order.save
				end
			else
				transaction = @transaction_service.process( order, args[:transaction] )
				if transaction && transaction.approved?
					order.status = 'active'
					order.save
					log_event( user: order.user, name: 'transaction_sxs', on: order, content: "transaction was approved for #{order.total_formatted} on Order #{order.code}" )
				elsif transaction && transaction.declined?
					log_event( user: order.user, name: 'transaction_failed', on: transaction.parent_obj, content: "transaction was denied for #{order.total_formatted} on Order #{order.code}: #{transaction.message}" )
				end
			end

			self.process_purchase_success( order, args ) if order.nested_errors.blank? && order.active?

			order.errors.add(:base, :processing_error, message: "Transaction was declined for #{order.total_formatted}" ) if order.declined? && order.errors.blank?

			transaction

		end

		def process_purchase_success( order, args = {} )
			transaction_options = args[:transaction] || {}

			begin
				@tax_service.process( order ) if @tax_service.respond_to? :process
			rescue Exception => e
				puts e.message
				NewRelic::Agent.notice_error(e) if defined?( NewRelic )
			end

			if order.user.nil? && order.email.present? && SwellEcom.create_user_on_checkout

				order.user = User.create_with( first_name: order.billing_address.first_name, last_name: order.billing_address.last_name ).find_or_create_by( email: order.email.downcase )
				order.billing_address.user = order.shipping_address.user = order.user
				order.save

			end

			payment_profile_expires_at = SwellEcom::TransactionService.parse_credit_card_expiry( transaction_options[:credit_card][:expiration] ) if transaction_options[:credit_card].present?
			@subscription_service.subscribe_ordered_plans( order, payment_profile_expires_at: payment_profile_expires_at ) if @subscription_service.present? && order.active?

			true
		end

		def refund( args = {} )

			@transaction_service.refund( args || {} )

		end

		def shipping_service
			@shipping_service
		end

		def subscription_service
			@subscription_service
		end

		def tax_service
			@tax_service
		end

		def transaction_service
			@transaction_service
		end

		def validate( order, args )
			return false if order.nested_errors.present?

			order.validate
			@shipping_service.validate( order.shipping_address )
			@shipping_service.validate( order.billing_address )
			@fraud_service.validate( order ) if @fraud_service

			return not( order.nested_errors.present? )
		end

		protected
		def calculate_order_before( order, args = {} )

			order.subtotal = order.order_items.select(&:prod?).sum(&:subtotal)
			order.status = 'pre_order' if order.order_items.select{|order_item| order_item.item.respond_to?( :pre_order? ) && order_item.item.pre_order? }.present?

		end

		def calculate_order_after( order, args = {} )

			order.total = order.order_items.sum(&:subtotal)

		end

		def process_capture_payment_method( order, args = {} )
			transaction = @transaction_service.capture_payment_method( order, args[:transaction] )
			order.save

			transaction
		end
	end

end
