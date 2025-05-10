# Ресурс для создания сети VPC в Yandex Cloud
resource "yandex_vpc_network" "oncall" {
  name      = "vpc"  # Имя сети VPC
}

# Ресурс для создания подсети в зоне "ru-central1-a"
resource "yandex_vpc_subnet" "oncall-a" {
  v4_cidr_blocks = ["10.0.1.0/24"]  # CIDR блок для подсети (IP-диапазон)
  zone           = "ru-central1-a"  # Зона, где будет размещена подсеть
  network_id     = yandex_vpc_network.oncall.id  # ID сети, к которой будет привязана подсеть
}

# Ресурс для создания подсети в зоне "ru-central1-b"
resource "yandex_vpc_subnet" "oncall-b" {
  v4_cidr_blocks = ["10.0.2.0/24"]  # CIDR блок для подсети (IP-диапазон)
  zone           = "ru-central1-b"  # Зона, где будет размещена подсеть
  network_id     = yandex_vpc_network.oncall.id  # ID сети, к которой будет привязана подсеть
}

# Ресурс для создания подсети в зоне "ru-central1-d"
resource "yandex_vpc_subnet" "oncall-d" {
  v4_cidr_blocks = ["10.0.3.0/24"]  # CIDR блок для подсети (IP-диапазон)
  zone           = "ru-central1-d"  # Зона, где будет размещена подсеть
  network_id     = yandex_vpc_network.oncall.id  # ID сети, к которой будет привязана подсеть
}
