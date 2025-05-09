# Получаем информацию о конфигурации клиента Yandex
data "yandex_client_config" "client" {}

# Создание сервисного аккаунта для управления Kubernetes
resource "yandex_iam_service_account" "sa-k8s-editor" {
  name      = "sa-k8s-editor"  # Имя сервисного аккаунта
}

# Назначение роли "editor" сервисному аккаунту на уровне папки
resource "yandex_resourcemanager_folder_iam_member" "sa-k8s-editor-permissions" {
  role      = "editor"  # Роль, дающая полные права на ресурсы папки
  folder_id = data.yandex_client_config.client.folder_id
  member = "serviceAccount:${yandex_iam_service_account.sa-k8s-editor.id}"  # Назначаемый участник
}

# Пауза, чтобы изменения IAM успели примениться до создания кластера
resource "time_sleep" "wait_sa" {
  create_duration = "20s"
  depends_on      = [
    yandex_iam_service_account.sa-k8s-editor,
    yandex_resourcemanager_folder_iam_member.sa-k8s-editor-permissions
  ]
}

# Создание Kubernetes-кластера в Yandex Cloud
resource "yandex_kubernetes_cluster" "gitlab-runner" {
  name       = "gitlab-runner"  # Имя кластера
  network_id = yandex_vpc_network.gitlab-runner.id  # Сеть, к которой подключается кластер

  master {
    version = "1.30"  # Версия Kubernetes мастера
    zonal {
      zone      = yandex_vpc_subnet.gitlab-runner-a.zone  # Зона размещения мастера
      subnet_id = yandex_vpc_subnet.gitlab-runner-a.id     # Подсеть для мастера
    }

    public_ip = true  # Включение публичного IP для доступа к мастеру
  }

  # Сервисный аккаунт для управления кластером и нодами
  service_account_id      = yandex_iam_service_account.sa-k8s-editor.id
  node_service_account_id = yandex_iam_service_account.sa-k8s-editor.id

  release_channel = "STABLE"  # Канал обновлений

  # Зависимость от ожидания применения IAM-ролей
  depends_on = [time_sleep.wait_sa]
}

# Группа узлов для Kubernetes-кластера
resource "yandex_kubernetes_node_group" "k8s-node-group" {
  description = "Node group for the Managed Service for Kubernetes cluster"
  name        = "k8s-node-group"
  cluster_id  = yandex_kubernetes_cluster.gitlab-runner.id
  version     = "1.30"  # Версия Kubernetes на нодах

  scale_policy {
    fixed_scale {
      size = 3  # Фиксированное количество нод
    }
  }

  allocation_policy {
    # Распределение нод по зонам отказоустойчивости
    location { zone = yandex_vpc_subnet.gitlab-runner-a.zone }
    location { zone = yandex_vpc_subnet.gitlab-runner-b.zone }
    location { zone = yandex_vpc_subnet.gitlab-runner-d.zone }
  }

  instance_template {
    platform_id = "standard-v2"  # Тип виртуальной машины

    network_interface {
      nat = true  # Включение NAT для доступа в интернет
      subnet_ids = [
        yandex_vpc_subnet.gitlab-runner-a.id,
        yandex_vpc_subnet.gitlab-runner-b.id,
        yandex_vpc_subnet.gitlab-runner-d.id
      ]
    }

    resources {
      memory = 20  # ОЗУ
      cores  = 4   # Кол-во ядер CPU
    }

    boot_disk {
      type = "network-ssd"         # Тип диска
      size = 128                   # Размер диска
    }
  }
}

# Настройка провайдера Helm для установки чарта в Kubernetes
provider "helm" {
  kubernetes {
    host                   = yandex_kubernetes_cluster.gitlab-runner.master[0].external_v4_endpoint  # Адрес API Kubernetes
    cluster_ca_certificate = yandex_kubernetes_cluster.gitlab-runner.master[0].cluster_ca_certificate  # CA-сертификат

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["k8s", "create-token"]  # Команда получения токена через CLI Yandex.Cloud
      command     = "yc"
    }
  }
}

# Установка ingress-nginx через Helm
resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.10.6"
  namespace        = "ingress-nginx"
  create_namespace = true
  depends_on       = [yandex_kubernetes_cluster.gitlab-runner]

  set {
    name  = "controller.service.loadBalancerIP"
    value = yandex_vpc_address.addr.external_ipv4_address[0].address  # Присвоение внешнего IP ingress-контроллеру
  }
}

# Вывод команды для получения kubeconfig
output "k8s_cluster_credentials_command" {
  value = "yc managed-kubernetes cluster get-credentials --id ${yandex_kubernetes_cluster.gitlab-runner.id} --external --force"
}
