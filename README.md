# Отправка label в систему логирования и мониторинга из метаданных GitLab Runner (job_id, pipeline_id)

## Введение — какую проблему решаем

При использовании GitLab CI/CD с Kubernetes возникает необходимость видеть связку между логами и конкретными CI job'ами 
или pipeline'ами. Это особенно полезно для отладки и мониторинга. Однако по умолчанию логи из подов не содержат этих 
связующих метаданных.

В данной статье мы покажем, как можно передавать метки `job_id`, `pipeline_id`, `project_name` и другие из GitLab Runner 
в систему логирования VictoriaLogs с помощью Promtail и систему мониторинга VictoriaMetrics.

## Почему используем VictoriaLogs, а не Loki

- **Мгновенный полнотекстовый поиск** по любым полям логов (включая высококардинальные, такие как job_id или pipeline_id), 
без необходимости предварительной настройки схемы. В Loki подобные запросы требуют осторожного управления метками и 
могут приводить к резкому росту потребления памяти.

- **Экономия ресурсов**: колоночное хранение как ClickHouse с автоматическим сжатием сокращает объём данных на диске в 
[5–10](https://docs.victoriametrics.com/victorialogs/faq/#what-is-the-difference-between-victorialogs-and-grafana-loki) раз по сравнению с Loki, а также ускоряет аналитические запросы.

- **Простота запросов**: интуитивный язык LogsQL удобен для фильтрации, агрегации и анализа, 
тогда как LogQL в Loki часто требует сложных конструкций для базовых задач.

- **Производительность**: типовые запросы выполняются до 
[1000x](https://docs.victoriametrics.com/victorialogs/faq/#what-is-the-difference-between-victorialogs-and-grafana-loki) 
быстрее, чем в Loki, благодаря оптимизированным алгоритмам индексации и отсутствию накладных расходов распределённых систем.

## Регистрация GitLab Runner в gitlab.com

Перед установкой runner'а необходимо зарегистрировать его в GitLab:

1. Перейдите в репозиторий GitLab.
2. Откройте `Settings -> CI/CD -> Runners`.
3. Выключите общие раннеры
4. Скопируйте registration token.

Этот токен понадобится для регистрации раннера в вашем Kubernetes-кластере.

## Установка Kubernetes

Установка kubernetes через terraform
```shell
git clone https://github.com/patsevanton/gitlab-job-labels-to-victorialogs
export YC_FOLDER_ID='ваш folder_id'
terraform init
terraform apply
```

## Установка VictoriaLogs
```bash
helm repo add vm https://victoriametrics.github.io/helm-charts/
helm repo update

helm upgrade --install victorialogs vm/victoria-logs-single \
  --namespace victorialogs --create-namespace \
  --values victorialogs-values.yaml
```

После установки, victorialogs будет доступен по адресу http://victorialogs.apatsev.org.ru

## Установка victoria-metrics-k8s-stack

Добавим Helm репозиторий и установим VictoriaMetrics stack:

```bash
helm repo add vm https://victoriametrics.github.io/helm-charts/
helm repo update

helm upgrade --install vmks vm/victoria-metrics-k8s-stack \
  --namespace vmks --create-namespace \
  --values vmks-values.yaml
```

В vmks-values.yaml указано что kube-state-metrics, разрешая экспорт всех метрик ([*]), связанных с подами (pods).
```shell
kube-state-metrics:
  metricLabelsAllowlist:
    - pods=[*]
```

Подробности в values kube-state-metrics и victoria-metrics-k8s-stack:
https://github.com/prometheus-community/helm-charts/blob/main/charts/kube-state-metrics/values.yaml#L397
https://github.com/VictoriaMetrics/helm-charts/blob/master/charts/victoria-metrics-k8s-stack/values.yaml#L975C1-L975C19

После установки, Grafana будет доступна по адресу http://grafana.apatsev.org.ru

Получение пароля grafana для admin юзера
```shell
kubectl get secret vmks-grafana -n vmks -o jsonpath='{.data.admin-password}' | base64 --decode
```



## Установка Promtail

```bash
helm upgrade --install promtail grafana/promtail \
  --namespace promtail --create-namespace \
  --values promtail-values.yaml
```

Файл конфигурации Promtail `promtail-values.yaml`:
```yaml
tolerations:
  - operator: Exists
    effect: NoSchedule
config:
  clients:
    - url: http://victorialogs-victoria-logs-single-server.victorialogs.svc.cluster.local:9428/insert/loki/api/v1/push?_msg_field=msg
  snippets:
    pipelineStages:
      - cri: {}
      - labeldrop:
          - filename
          - node_name
    extraRelabelConfigs:
      - source_labels: [__meta_kubernetes_namespace]
        action: keep
        regex: gitlab-runner
```


## Установка GitLab Runner через Helm:
```bash
helm repo add gitlab https://charts.gitlab.io
helm repo update

export RUNNER_TOKEN="glrt-xxx.xxxxx"  # экспортируйте gitlab-runner токен

helm upgrade --install gitlab-runner gitlab/gitlab-runner \
  --namespace gitlab-runner --create-namespace \
  --values gitlab-runner-values.yaml \
  --set-string runnerToken="$RUNNER_TOKEN"
```

Пример `gitlab-runner-values.yaml`:
```yaml
gitlabUrl: "https://gitlab.com/"
runners:
  config: |
    [[runners]]
      [runners.kubernetes]
        helper_cpu_request = "250m"
        helper_memory_limit = "512Mi"
        [runners.kubernetes.pod_labels]
          "job_name" = "${CI_JOB_NAME_SLUG}"
          "job_id" = "${CI_JOB_ID}"
          "project_name" = "${CI_PROJECT_NAME}"
          "project_id" = "${CI_PROJECT_ID}"
          "pipeline_id" = "${CI_PIPELINE_ID}"
metrics:
  enabled: true
  serviceMonitor:
    enabled: true
service:
  enabled: true
rbac:
  create: true
```

### Проверка, что у pod есть label
Запустите сборку на этом раннере и проверьте label
Должно быть примерно так
```shell
kubectl get pod -n gitlab-runner --show-labels | grep -E '(job_name|job_id|project_name|project_id|pipeline_id)'
runner-sijwob5yi-project-69309276-concurrent-0-7hr533es   2/2     Running   0          16s     ...,job_id=9895041344,job_name=deploy-job,pipeline_id=1796027502,pod=runner-sijwob5yi-project-69309276-concurrent-0,project_id=69309276,project_name=gitlab-for-job-labels-to-victorialogs
runner-sijwob5yi-project-69309276-concurrent-0-pfirp5t5   2/2     Running   0          49s     ...,job_id=9895041322,job_name=unit-test-job,pipeline_id=1796027502,pod=runner-sijwob5yi-project-69309276-concurrent-0,project_id=69309276,project_name=gitlab-for-job-labels-to-victorialogs
runner-sijwob5yi-project-69309276-concurrent-1-85wx1m9n   2/2     Running   0          44s     ...,job_id=9895041335,job_name=lint-test-job,pipeline_id=1796027502,pod=runner-sijwob5yi-project-69309276-concurrent-1,project_id=69309276,project_name=gitlab-for-job-labels-to-victorialog
```

## Отображение failed строк в логах с фильтрацией по `job_id`
Failed строка появляется не в pod `runner-xxx-project-yyy-concurrent-0-zzz`, а в pod `gitlab-runner-xxx-yyy`. Вот [issue](https://gitlab.com/gitlab-org/gitlab-runner/-/issues/38777)
Поэтому для отображения failed строк при падении job необходимо использовать after_script с проверкой $CI_JOB_STATUS
Пример gitlab-ci.yaml:
```yaml
image: alpine:latest
stages:
  - build
  - test
  - deploy
build-job:
  stage: build
  script:
    - echo "$CI_JOB_ID"
    - exit 1
  allow_failure: true
  after_script:
    - |
      if [ "$CI_JOB_STATUS" != "success" ]; then
        echo "ERROR: Job failed: command terminated with non-zero exit code"
      fi
```

## Просмотр как это выглядит в VictoriaLogs

1. Зайдите в UI VictoriaLogs (обычно на `/select/`) или подключитесь к Grafana.
2. Выполните запросы с фильтрацией по `job_id`, `pipeline_id`, например:
```
pipeline_id: "1809184207" job_id: "9984945726"
```
или
```
{job_id="9984945726",pipeline_id="1809184207"}
```

Теперь вы можете фильтровать логи по job, pipeline и другим CI-метаданным,
что значительно упрощает отладку и мониторинг процессов.

![Скриншот victorialogs](victorialogs.png)

## Grafana Dashboard
Импортируйте дашборд dashboard.json
В Grafana будут видны метки, переданные из GitLab Runner (`job_id`, `pipeline_id` и т.д.).
Выглядит вот так:
![Скриншот Grafana](grafana_screenshot.png)

## Удаление через terraform
```shell
terraform destroy
```

## Заключение

Теперь вы можете легко отслеживать, какие логи/метрики относятся к какому pipeline и job'у. Использование VictoriaLogs 
позволяет справляться с большим объемом уникальных меток. Этот подход хорошо масштабируется и обеспечивает гибкую, 
но мощную систему обсервабилити для CI/CD процессов в Kubernetes. С добавлением всего нескольких строк в конфигурацию 
вы получаете мощный инструмент для мониторинга и отладки CI/CD pipeline'ов.

## Опрос: Делать ли телеграм канал?
