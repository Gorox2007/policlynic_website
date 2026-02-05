class RoleRouter:
    route_app_labels = {
        'client_app': 'client',  # только SELECT
        'operator_app': 'default',  # ORM и миграции через default
    }

    def db_for_read(self, model, **hints):
        return self.route_app_labels.get(model._meta.app_label, 'default')

    def db_for_write(self, model, **hints):
        return self.route_app_labels.get(model._meta.app_label, 'default')

    def allow_migrate(self, db, app_label, model_name=None, **hints):
        return db == 'default'
