# Foco Simples

Aplicativo de produtividade desenvolvido em Flutter para organizar períodos de concentração, estudo, trabalho e descanso.

**Seu tempo, seu ritmo.**

<p align="center">
  <img src="docs/images/banner.png" alt="Foco Simples" width="900">
</p>

## O que é este repositório

Este repositório foi preparado para apresentar o **Foco Simples** como projeto de portfólio e disponibilizar os arquivos de referência para estudo e montagem em uma máquina local.

Ele **não contém chaves de assinatura, credenciais privadas nem a configuração particular do ambiente do desenvolvedor**.

O código Flutter principal está em:

```text
arquivos/main.dart
```

E há um script auxiliar para aplicar esse arquivo sobre um projeto Flutter existente:

```bash
chmod +x aplicar_linux.sh
./aplicar_linux.sh
```

Por padrão, o script procura o projeto em:

```text
~/Documentos/foco_simples
```

Para usar outro diretório:

```bash
./aplicar_linux.sh /caminho/para/seu/projeto
```

## Funcionalidades apresentadas

- Cronômetro configurável
- Seleção de horas, minutos e segundos
- Limite de até 24 horas
- Modo Pomodoro
- Pausas curtas e longas
- Perfis personalizados
- Estatísticas locais de concentração
- Alertas por som, vibração ou modo silencioso
- Recuperação do cronômetro
- Interface com progresso circular
- Funcionamento sem login
- Sem anúncios

## Como preparar em sua máquina

### 1. Instale os pré-requisitos

Você precisará de:

- Flutter
- Dart
- Java
- Android SDK

Confira o ambiente com:

```bash
flutter doctor -v
```

### 2. Tenha um projeto Flutter existente

O script deste repositório aplica o `main.dart` de referência em um projeto já criado.

Exemplo:

```bash
flutter create foco_simples
```

Depois, ajuste o projeto Android conforme as necessidades do aplicativo.

### 3. Aplique os arquivos

Na raiz deste repositório:

```bash
chmod +x aplicar_linux.sh
./aplicar_linux.sh /caminho/para/foco_simples
```

### 4. Teste

```bash
cd /caminho/para/foco_simples
flutter run
```

### 5. Gere um pacote Android

APK:

```bash
flutter build apk --release
```

Android App Bundle:

```bash
flutter build appbundle --release
```

## Observação importante sobre recursos Android

O código usa integração nativa para recursos como alertas, notificações, persistência e comportamento em segundo plano.

Por isso, ao montar o projeto do zero, pode ser necessário complementar a configuração Android nativa além do `main.dart`.

Este repositório é uma **referência técnica e de portfólio**, não um instalador universal do aplicativo.

## Privacidade

O Foco Simples não exige cadastro ou login.

As configurações, perfis e estatísticas são mantidos localmente no dispositivo.

Política pública:

https://sites.google.com/view/qacom-foco-simples-privacidade

## Google Play

O projeto passou pelas etapas de teste interno e teste fechado do Google Play durante seu desenvolvimento.

O nome do pacote utilizado no projeto original é:

```text
br.com.qacom.foco_simples
```

## Segurança

Nunca coloque no GitHub:

```text
android/key.properties
*.jks
*.keystore
.env
tokens
senhas
chaves privadas
```

Esses arquivos estão explicitamente ignorados pelo `.gitignore` deste repositório.

## Estrutura

```text
foco_simples/
├── arquivos/
│   └── main.dart
├── docs/
│   └── images/
├── aplicar_linux.sh
├── CHANGELOG.md
├── PRIVACY.md
├── SECURITY.md
├── .gitignore
└── README.md
```

## Status

Projeto em evolução.

A documentação pública foi preparada para permitir que outros desenvolvedores entendam a proposta, estudem a implementação e configurem o projeto em seu próprio ambiente.
