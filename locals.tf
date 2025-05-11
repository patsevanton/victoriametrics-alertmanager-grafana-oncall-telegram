# Получаем информацию о конфигурации клиента Yandex
data "yandex_client_config" "client" {}

# Генерация случайного пароля для PostgreSQL
resource "random_password" "postgres" {
  length      = 20            # Длина пароля 20 символов
  special     = false          # Без специальных символов
  min_numeric = 4             # Минимум 4 цифры в пароле
  min_upper   = 4             # Минимум 4 заглавные буквы в пароле
}

# Локальные переменные для настройки инфраструктуры
locals {
  postgres_password   = random_password.postgres.result # Сгенерированный пароль для PostgreSQL
}
