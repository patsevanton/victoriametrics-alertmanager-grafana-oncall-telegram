# Создание внешнего IP-адреса в Yandex Cloud
resource "yandex_vpc_address" "addr" {
  name = "gitlab-runner-pip"  # Имя ресурса внешнего IP-адреса

  external_ipv4_address {
    zone_id = yandex_vpc_subnet.gitlab-runner-a.zone  # Зона доступности, где будет выделен IP-адрес
  }
}

# Создание публичной DNS-зоны в Yandex Cloud DNS
resource "yandex_dns_zone" "apatsev-org-ru" {
  name  = "apatsev-org-ru-zone"  # Имя ресурса DNS-зоны

  zone  = "apatsev.org.ru."      # Доменное имя зоны (с точкой в конце)
  public = true                  # Указание, что зона является публичной

  # Привязка зоны к VPC-сети, чтобы можно было использовать приватный DNS внутри сети
  private_networks = [yandex_vpc_network.gitlab-runner.id]
}

# Создание DNS-записи типа A, указывающей на внешний IP
resource "yandex_dns_recordset" "grafana" {
  zone_id = yandex_dns_zone.apatsev-org-ru.id       # ID зоны, к которой принадлежит запись
  name    = "grafana.apatsev.org.ru."                # Полное имя записи (поддомен)
  type    = "A"                                     # Тип записи — A (IPv4-адрес)
  ttl     = 200                                     # Время жизни записи в секундах
  data    = [yandex_vpc_address.addr.external_ipv4_address[0].address]  # Значение — внешний IP-адрес, полученный ранее
}

# Создание DNS-записи типа A, указывающей на внешний IP
resource "yandex_dns_recordset" "victorialogs" {
  zone_id = yandex_dns_zone.apatsev-org-ru.id       # ID зоны, к которой принадлежит запись
  name    = "victorialogs.apatsev.org.ru."                # Полное имя записи (поддомен)
  type    = "A"                                     # Тип записи — A (IPv4-адрес)
  ttl     = 200                                     # Время жизни записи в секундах
  data    = [yandex_vpc_address.addr.external_ipv4_address[0].address]  # Значение — внешний IP-адрес, полученный ранее
}
