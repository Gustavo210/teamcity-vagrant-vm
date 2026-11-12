# TeamCity Agent - Ubuntu VM

VM Ubuntu 22.04 que roda um agente TeamCity via Docker, com suporte para **libvirt** e **VirtualBox**.

## Recursos da VM

| Recurso             | Valor                               |
| ------------------- | ----------------------------------- |
| Sistema Operacional | Ubuntu 22.04 (`generic/ubuntu2204`) |
| CPUs                | 4 (fixadas nos threads 6, 7, 14 e 15 do host, libvirt) |
| RAM                 | 6 GB                                |
| Disco               | 150 GB                              |
| Agente              | `jetbrains/teamcity-agent:2025.07.1` (mesma versão do servidor) |
| Fuso horário        | America/Sao_Paulo (VM e container)  |

## Pré-requisitos

- **Vagrant** - [Guia de instalação](https://developer.hashicorp.com/vagrant/install)
- Um provider de virtualização:
  - **Libvirt** - [Plugin vagrant-libvirt](https://vagrant-libvirt.github.io/vagrant-libvirt/)
  - **VirtualBox** - [Download](https://www.virtualbox.org/wiki/Downloads)
    - Plugin para disco: `vagrant plugin install vagrant-disksize`

## Configuração

Copie o arquivo de exemplo e edite com seus valores:

```bash
cp .env.example .env
```

```env
AGENT_NAME=meu-agente
SERVER_URL=http://IP_DO_SERVIDOR:8111
```

| Variável     | Descrição                  | Default                                       |
| ------------ | -------------------------- | --------------------------------------------- |
| `AGENT_NAME` | Nome do agente no TeamCity | `ubuntu-teamcity-agent`                       |
| `SERVER_URL` | URL do servidor TeamCity   | `http://LOCAL_COMPANY_SERVER_IP_ADDRESS:8111` |
| `TELEGRAM_BOT_TOKEN` | Token do bot para alertas (opcional) | vazio, alertas desligados |
| `TELEGRAM_CHAT_ID`   | Chat que recebe os alertas (opcional) | vazio                    |
| `DISK_ALERT_PERCENT` | Uso de disco que dispara o alerta     | `85`                     |

## Uso

### Subir a VM

```bash
vagrant up
```

O provisionamento executa automaticamente:

1. Desativa DNSSEC no `systemd-resolved` (o padrão da box quebra o DNS)
2. Corrige o mirror de pacotes Ubuntu (usa `archive.ubuntu.com`)
3. Desativa o unattended-upgrades (ele podia atualizar e reiniciar o Docker no meio de um build)
   e define o fuso horário America/Sao_Paulo
4. Expande a partição, o LVM e o ext4 da raiz até ocupar o disco virtual inteiro
   (a box vem com um LV de 63 GB mesmo com disco de 150 GB)
5. Instala Docker com buildx e compose v2, e grava `/etc/docker/daemon.json` com rotação de
   logs dos containers e teto de 50 GB para o cache de build do BuildKit (o padrão é 10 GB, e o
   GC descarta o cache menos usado primeiro, o que apagava o cache de builds raros como a imagem
   Android)
6. Habilita o daemon Docker e adiciona vagrant ao grupo docker
7. Agenda limpeza semanal em `/etc/cron.weekly/docker-prune`: só imagens sem tag e containers
   parados há mais de 7 dias. Cache de build, imagens com tag e volumes nomeados são preservados
8. Instala o alerta por Telegram (`scripts/agent-alert.sh`) com cron a cada 15 minutos
9. Builda a imagem do agente TeamCity
10. Grava `teamcity.agent.build.checkoutDir.expireHours=never` em
    `/opt/buildagent/conf/buildAgent.properties` (o padrão do TeamCity apaga diretórios
    de checkout sem uso há 192 h)
11. Recria o container do agente com volumes para conf, logs, work, temp, tools, plugins e system

### Acessar a VM

```bash
vagrant ssh
```

### Verificar o agente

```bash
vagrant ssh -c "docker ps"
vagrant ssh -c "docker logs teamcity-agent"
```

### Espaço em disco

Para ver o que está ocupando o disco e liberar espaço manualmente:

```bash
vagrant ssh -c "df -h / && docker system df"
vagrant ssh -c "sudo /etc/cron.weekly/docker-prune"
```

Se o disco virtual for aumentado no `Vagrantfile`, basta rodar `vagrant provision`
(ou só o bloco "Growing root filesystem" do `provision.sh`) para a raiz crescer junto.

O cache de build só é podado pelo próprio BuildKit quando passar de 50 GB, começando pelo
menos usado. Para mudar o teto, edite `defaultKeepStorage` no `daemon.json` e reinicie o Docker
(a configuração só é lida na subida do daemon).

Os diretórios de checkout em `/opt/buildagent/work` nunca expiram (`expireHours=never`).
Para voltar ao padrão de 8 dias, troque o valor por `default` em
`/opt/buildagent/conf/buildAgent.properties`; o agente reinicia sozinho ao detectar a mudança.
A configuração do agente (incluindo o `authorizationToken`) fica no host em `/opt/buildagent/conf`,
então recriar o container não exige autorizar o agente de novo no servidor.

### Alertas no Telegram

O script `scripts/agent-alert.sh` roda a cada 15 minutos na VM e avisa quando o disco passa de
`DISK_ALERT_PERCENT` ou quando o container do agente para, mais uma mensagem quando normaliza.
Ele só manda mensagem quando o estado muda, então um disco cheio gera um aviso, não um por ciclo.

1. Crie um bot no [@BotFather](https://t.me/BotFather) e copie o token.
2. Mande qualquer mensagem para o bot e abra `https://api.telegram.org/bot<TOKEN>/getUpdates`
   para ler o `chat.id`.
3. Preencha `TELEGRAM_BOT_TOKEN` e `TELEGRAM_CHAT_ID` no `.env` e rode `vagrant provision`,
   ou edite `/etc/teamcity-agent-alert.env` direto na VM.
4. Teste: `vagrant ssh -c "sudo teamcity-agent-alert --test"`.

### Snapshot antes de manutenção

Com libvirt, tire um snapshot do domínio antes de mexer na VM (inclui disco e memória):

```bash
virsh -c qemu:///system snapshot-create-as teamcity-arch-vm_default pre-manutencao "descrição" --atomic
virsh -c qemu:///system snapshot-list teamcity-arch-vm_default
virsh -c qemu:///system snapshot-revert teamcity-arch-vm_default pre-manutencao   # voltar
virsh -c qemu:///system snapshot-delete teamcity-arch-vm_default pre-manutencao   # descartar
```

### CPU dedicada (libvirt)

Os 4 vCPUs ficam fixos nos threads 6, 7, 14 e 15 do host (dois núcleos físicos inteiros, com
seus pares de hyperthreading) via `lv.cpuset`, com `cpu_mode = host-passthrough`. Isso vale na
criação do domínio; para uma VM já existente, rode os comandos `virsh vcpupin` comentados no
`Vagrantfile`. Para o host nunca escalonar nada nesses threads, seria preciso
`isolcpus=6,7,14,15` na linha de comando do kernel do host, o que não está feito.

Mudar `lv.cpus` ou `lv.memory` de uma VM existente: o vagrant-libvirt 0.12.2 falha ao aplicar
memória com o domínio desligado e deixa a VM parada. Nesse caso, grave os valores direto no
domínio e depois suba:

```bash
virsh -c qemu:///system setmaxmem teamcity-arch-vm_default 6291456 --config
virsh -c qemu:///system setmem    teamcity-arch-vm_default 6291456 --config
virsh -c qemu:///system setvcpus  teamcity-arch-vm_default 4 --maximum --config
virsh -c qemu:///system setvcpus  teamcity-arch-vm_default 4 --config
vagrant up
```

### Parar a VM

```bash
vagrant halt
```

### Destruir a VM

```bash
vagrant destroy -f
```

### Re-provisionar (sem recriar a VM)

```bash
vagrant provision
```

O container do agente é recriado no fim do provisionamento. Rode apenas com o agente ocioso.

## Auto-start no boot

### Libvirt

Já configurado automaticamente via `lv.autostart = true`.

### VirtualBox

Copie e ative o serviço systemd:

```bash
sudo cp teamcity-agent-vm.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable teamcity-agent-vm.service
```

## Estrutura do projeto

```
.
├── .env.example              # Exemplo de variáveis de ambiente
├── Dockerfile.agent          # Imagem Docker do agente TeamCity
├── provision.sh              # Instalação do Docker e deploy do agente
├── scripts/agent-alert.sh    # Alertas de disco e agente via Telegram
├── teamcity-agent-vm.service # Serviço systemd para auto-start (VirtualBox)
└── Vagrantfile               # Definição da VM (Ubuntu 22.04)
```
