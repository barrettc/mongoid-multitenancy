module Mongoid
  module Multitenancy
    module Document
      extend ActiveSupport::Concern

      module ClassMethods

        attr_accessor :tenant_field

        def tenant(association = :account, options={})
          tenant_options = { optional: options.delete(:optional), immutable: options.delete(:immutable) { true } }
          # Setup the association between the class and the tenant class
          # TODO: should index this association if no other indexes are defined => , index: true
          belongs_to association, options

          # Get the tenant model and its foreign key
          tenant_field = reflect_on_association(association).foreign_key
          self.tenant_field = tenant_field

          # Validates the tenant field
          validates tenant_field, tenant: tenant_options

          # Set the current_tenant on newly created objects
          before_validation lambda { |m|
            if Multitenancy.current_tenant and !tenant_options[:optional] and m.send(association.to_sym).nil?
              m.send "#{association}=".to_sym, Multitenancy.current_tenant
            end
            true
          }

          # Set the default_scope to scope to current tenant
          default_scope lambda {
            criteria = if Multitenancy.current_tenant
              if tenant_options[:optional]
                #any_of({ self.tenant_field => Multitenancy.current_tenant.id }, { self.tenant_field => nil })
                where({ tenant_field.to_sym.in => [Multitenancy.current_tenant.id, nil] })
              else
                where({ tenant_field => Multitenancy.current_tenant.id })
              end
            else
              where(nil)
            end
          }
        end

        # Redefine 'validates_with' to add the tenant scope when using a UniquenessValidator
        def validates_with(*args, &block)
          if args.first == Validatable::UniquenessValidator
            args.last[:scope] = Array(args.last[:scope]) << self.tenant_field
          end
          super(*args, &block)
        end

        # Redefine 'index' to include the tenant field in first position
        def index(spec, options = nil)
          spec = { self.tenant_field => 1 }.merge(spec)
          super(spec, options)
        end

        # Redefine 'delete_all' to take in account the default scope
        def delete_all(conditions = nil)
          scoped.where(conditions).delete
        end
      end
    end
  end
end
