# TeamCity Agent - Arch Linux VM

VM Arch Linux que roda um agente TeamCity via Docker, com suporte para **libvirt** e **VirtualBox**.

## Recursos da VM

| Recurso | Valor |
|---|---|
| Sistema Operacional | Arch Linux (`generic/arch`) |
| CPUs | 2 |
| RAM | 4 GB |
| Disco | 150 GB |

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

| Variável | Descrição | Default |
|---|---|---|
| `AGENT_NAME` | Nome do agente no TeamCity | `arch-teamcity-agent` |
| `SERVER_URL` | URL do servidor TeamCity | `http://LOCAL_COMPANY_SERVER_IP_ADDRESS:8111` |

## Uso

### Subir a VM

```bash
# Com libvirt
vagrant up --provider=libvirt

# Com VirtualBox
vagrant up --provider=virtualbox
```

O provisionamento executa automaticamente:

1. Atualiza o keyring e o sistema (incluindo kernel)
2. Reinicia a VM com o kernel atualizado
3. Instala Docker
4. Builda a imagem do agente TeamCity
5. Sobe o container do agente

### Acessar a VM

```bash
vagrant ssh
```

### Verificar o agente

```bash
vagrant ssh -c "docker ps"
vagrant ssh -c "docker logs teamcity-agent"
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
├── provision-base.sh         # Atualização do sistema e kernel
├── provision.sh              # Instalação do Docker e deploy do agente
├── teamcity-agent-vm.service # Serviço systemd para auto-start (VirtualBox)
└── Vagrantfile               # Definição da VM
```
