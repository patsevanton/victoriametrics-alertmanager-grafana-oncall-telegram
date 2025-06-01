## Введение

Мониторинг позволяет вовремя выявлять проблемы в системе, а оповещения через такие инструменты, как Alertmanager и Grafana OnCall, помогают команде быстро реагировать. В статье описано, как связать между собой различные инструменты, чтобы инцидент автоматически отслеживался от правила мониторинга до уведомления в мессенджере.

## Преимущества маршрутизации алертов через OnCall

Если слать алерты напрямую из Alertmanager в Telegram, уведомления всегда будут приходить в один и тот же чат или нескольким людям сразу, что неудобно при сменах дежурств и может привести к потере ответственности — все видят сообщение, но никто не обязан реагировать. Нет удобного контроля, кто сейчас отвечает, сложно отличить рабочие часы от нерабочих, невозможно управлять графиком дежурств.

Если же передавать оповещения из Alertmanager в Grafana OnCall, а уже оттуда — в Telegram, появляются важные преимущества. Grafana OnCall позволяет вести расписание дежурств: вы указываете, кто и когда на смене, и только этот человек получает уведомление. Также доступна эскалация — если дежурный не отреагировал за определённое время, алерт пересылается следующему ответственному или целой группе, чтобы инцидент не остался без внимания. Через Grafana OnCall можно подтвердить получение сообщения ("Acknowledge").

Таким образом, связка `Alertmanager → Grafana OnCall → Telegram` обеспечивает централизованный, управляемый и прозрачный процесс реагирования на инциденты, автоматизирует учёт дежурств, поддерживает эскалацию и позволяет отслеживать подтверждение алертов.

## Общая схема прохождения алерта

### Диаграмма прохождения алерта

```
Prometheus Rule → vmalert → Alertmanager → Grafana OnCall → Telegram
```

Эта диаграмма отражает основной путь прохождения алерта — от возникновения события в метриках до получения уведомления в мессенджере ответственным сотрудником.

## VMAlert: обработка и маршрутизация алертов

### Что такое VMAlert

**VMAlert** — это компонент стека мониторинга VictoriaMetrics, предназначенный для оценки правил алертинга (alerting rules) в стиле Prometheus и генерации алертов на их основе. VMAlert берет на вход файл (или список файлов) с alert rule'ами, периодически опрашивает метрики (как правило, из VictoriaMetrics или Prometheus-compatible источников), вычисляет выражения и при их срабатывании формирует события алерта. Далее он направляет сформированные алерты в Alertmanager для дальнейшей маршрутизации и обработки.

### Архитектура решения
В данной архитектуре для мониторинга метрик используется Prometheus-совместимая система — VictoriaMetrics с её компонентом vmalert. Сначала создаётся alert rule (правило срабатывания) и применяется к vmalert. Как только условие правила выполняется, vmalert формирует алерт и отправляет его в Alertmanager. Alertmanager занимается маршрутизацией алертов, их группировкой, устранением дублирования и переадресацией по настройкам. Следующий этап — передача алерта из Alertmanager в Grafana OnCall, который уже отвечает за координацию оповещений: учитывает расписания дежурных, каналы связи и собственную логику эскалаций. После обработки события в OnCall ответственным лицам отправляется уведомление — в нашем случае посредством Telegram.

Такой подход позволяет гибко настроить процесс реагирования на инциденты: алерты по цепочке проходят через все нужные этапы фильтрации, маршрутизации и эскалации для быстрого и адресного оповещения нужных сотрудников.

## Установка Kubernetes

Установка kubernetes через terraform:

```shell
git clone https://github.com/patsevanton/gitlab-job-labels-to-victorialogs
export YC_FOLDER_ID='ваш folder_id'
terraform init
terraform apply
```

## Установка Prometheus Operator CRDs

Используем Prometheus Operator CRDs потому что еще много алертов находится в формате `kind: PrometheusRule`.

```shell
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install --wait prometheus-operator-crds prometheus-community/prometheus-operator-crds --version 20.0.0
```

## Особенность интеграции telegram c OnCall

Для работы интеграции telegram c OnCall необходимо, чтобы OnCall был доступен в интернете по HTTPS.  
Поэтому в чарте OnCall присутствует следующий код:

```yaml
ingress:
  annotations:
    cert-manager.io/issuer: "letsencrypt-prod"
    kubernetes.io/ingress.class: nginx
```

## Установка OnCall helm чарта

```shell
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm upgrade --install --wait \
    oncall grafana/oncall \
    --namespace oncall --create-namespace \
    --version 1.3.62 \
    --values oncall-values.yaml
```

## Установка victoria-metrics-k8s-stack

Добавим Helm репозиторий и установим VictoriaMetrics stack:

```shell
helm repo add vm https://victoriametrics.github.io/helm-charts/
helm repo update
helm upgrade --install --wait \
    vmks vm/victoria-metrics-k8s-stack \
    --namespace vmks --create-namespace \
    --version 0.46.0 \
    --values vmks-values.yaml
```

### Создание правила для тестирования цепочки

Для тестирования всей цепочки алерта создайте простое правило, которое будет алертить всегда. Это позволит убедиться, что весь процесс — от генерации события до получения уведомления в Telegram — работает корректно.

Создадим yaml-файл `always-fire-rule.yaml`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: always-fire-rule
  labels:
    prometheus: k8s
    role: alert-rules
spec:
  groups:
    - name: always-fire
      rules:
        - alert: AlwaysFiring
          expr: 1 == 1
          for: 1m
          labels:
            severity: critical
          annotations:
            summary: "Тестовое оповещение: Always firing"
            description: "Это тестовый алерт для проверки прохождения цепочки уведомлений."
```

Применяем его:

```shell
kubectl apply -f alert-always-fire.yaml
```

Это правило срабатывает всегда, поскольку выражение `1 == 1` истинно. Мы задаём продолжительность `for: 1m`, после чего алерт переходит в состояние firing. Метки и аннотации пригодятся для идентификации тестового оповещения при просмотре в Grafana OnCall или Telegram.

## Установка плагина OnCall в Grafana

Grafana будет доступна по адресу: `http://grafana.apatsev.org.ru`.

Получение пароля для admin юзера:

```shell
kubectl get secret vmks-grafana -n vmks -o jsonpath='{.data.admin-password}' | base64 --decode
```

Мне удалось настроить OnCall плагин только через UI. В конце будут приведены разные ошибки при попытке настройке Oncall плагина. Итак, для настройки плагина OnCall через UI необходимо:

1. Откройте Grafana.  
2. Перейдите в:  
   `Home` → `Administration` → `Plugins and data` → `Grafana OnCall` → `Configuration`.  
3. Укажите адрес OnCall: `http://oncall-engine.oncall:8080`.  
4. Нажмите Connect.

## Интеграция с Alertmanager
Для интеграции Alertmanager с Grafana OnCall добавьте соответствующий получатель (receiver) с webhook-URL, предоставленным OnCall.  
Пример части values для victoria-metrics-k8s-stack (трафик алертов идет в oncall):

```yaml
- name: 'oncall-webhook'
  webhook_configs:
    - url: 'http://oncall-engine.oncall:8080/integrations/v1/alertmanager/token/'
      send_resolved: true
```

В этом примере создаётся receiver (получатель) с именем `oncall-webhook`, который использует webhook для отправки
алертов напрямую в Grafana OnCall. В URL указывается уникальный путь интеграции и ключ, который можно получить в
настройках Grafana OnCall для вашей службы. Опция `send_resolved` позволяет уведомлять OnCall также о том, что
алерт был устранён.

## Подключение источника алертов

Для интеграции Grafana OnCall c системой мониторинга, построенной на базе Prometheus и VictoriaMetrics, необходимо
корректно связать цепочку генерации и доставки алертов:  
Prometheus генерирует alert согласно заданным правилам и отправляет их в компонент vmalert (часть VictoriaMetrics),
который транслирует эти алерты в Alertmanager. Alertmanager, в свою очередь, выполняет агрегацию, группировку и
маршрутизацию алертов, а затем пересылает их в Grafana OnCall.

Чтобы Alertmanager мог отправлять алерты в Grafana OnCall, нужно в конфигурационный файл Alertmanager (обычно это
`alertmanager.yml`) добавить новый webhook receiver с endpoint, предоставляемым OnCall. Затем, в пользовательском
интерфейсе OnCall, создаётся интеграция типа Alertmanager, где система генерирует URL, на который должны приходить
алерты. Этот адрес и указывается в Alertmanager.

После этого все алерты, направленные на receiver `grafana-oncall`, будут поступать в Grafana OnCall для
дальнейшей обработки.

### Интеграции OnCall и Alertmanager

Создайте integration:

1. В Grafana: `Home` → `Alerts & IRM` → `OnCall` → `Integrations`.
2. Создайте integration типа `alertmanager` с именем `alertmanager-intergration`.
3. Получите URL для интеграции:

   ```
   https://oncall.apatsev.org.ru/integrations/v1/alertmanager/token/
   ```

   (Используйте внутренний адрес:
   `http://oncall-engine.oncall:8080/integrations/v1/alertmanager/token/`)

4. Активируйте webhook_configs в файле `vmks-values.yaml` и обновите victoria-metrics-k8s-stack:

```shell
helm upgrade --install --wait \
    vmks vm/victoria-metrics-k8s-stack \
    --namespace vmks --create-namespace \
    --version 0.46.0 \
    --values vmks-values.yaml
```

Почему-то слетает подключение плагина OnCall. Поэтому подключаем его снова.
- Открываем Grafana
- Перейти `Home` -> `Administration` -> `Plugins and data` -> `Grafana OnCall` -> `Configuration`
- Указать адрес oncall: `http://oncall-engine.oncall:8080`
- Нажать connect

## Настройка расписания дежурств

В Grafana:  
`Home` → `Alerts & IRM` → `OnCall` → `Schedules`  
Создайте новое расписание `demo-schedule`, добавьте ротацию, выберите `weeks`, активируйте маску по дням (`Mo`, `Tu`, `We`, `Th`, `Fr`), укажите пользователя (например, admin).

## Настройка цепочки эскалации

В Grafana:  
`Home` → `Alerts & IRM` → `OnCall` → `Escalation chains`  
Создайте цепочку эскалации `demo-escalation-chain` с оповещением пользователей из расписания, выберите `demo-schedule`.

## Подключение цепочки эскалации к integration

В Grafana:  
`Home` → `Alerts & IRM` → `OnCall` → `Integrations`  
Откройте `alertmanager-intergration`, добавьте route:

```
{{ payload.commonLabels.severity == "critical" }}
```

Подключите цепочку эскалации `demo-escalation-chain`.

## Настройка Grafana OnCall для оповещения в Telegram

### Указание telegram token

Для telegram polling обязательно указывайте telegram token — иначе будут ошибки (`telegram.error.InvalidToken: Invalid token`). Для этого пропишите telegram token в env (`oncall-values.yaml`) или задайте через UI:  
`Home` → `Alerts & IRM` → `OnCall` → `Settings` → `ENV Variable` → `TELEGRAM_TOKEN`

![](edit_telegram_token_in_env_var.png)

Далее активируйте telegram polling и обновите OnCall:

```shell
helm upgrade --install --wait \
    oncall grafana/oncall \
    --namespace oncall --create-namespace \
    --version 1.3.62 \
    --values oncall-values.yaml
```

При установке Oncall plugin версии 1.3.118 отсутствует возможность редактировать `TELEGRAM_TOKEN` через `ENV Variable`

### Получение алертов в личных сообщениях Telegram

Чтобы получать нотификации в своих личных сообщениях Telegram и иметь возможность выполнять действия (подтвердить,
решить, перевести оповещение в безвучный режим) прямо из чата:

1. В Grafana:  
   `Home` → `Alerts & IRM` → `OnCall` → `Users`.
2. Нажмите "View my profile".
3. Найдите настройку Telegram, нажмите "Connect account".
4. Для автоматического подключения — "Connect automatically", скопируйте секрет и вставьте в Telegram боте.
5. Укажите Telegram в `Default Notifications` и `Important Notifications`.

![](default_notifications_to_telegram.png)


## Алерт в telegram

Алерт в telegram выглядит так:  
![alert_in_telegram.png](alert_in_telegram.png)  
Можно нажать resolve или перевести оповещение в безвучный режим.


## Заключение

Интеграция Grafana OnCall с Telegram — это быстрый способ организовать современную командную коммуникацию по инцидентам без бюрократии. Grafana OnCall предоставляет централизованную платформу для эффективного управления алертами и инцидентами. Простота интеграции с инструментами мониторинга и такими платформами, как Telegram, делает инструмент гибким и удобным: каждый инцидент доходит до ответственного сотрудника. Интерфейс интуитивно понятен и поддерживает масштабирование под любые команды.
