<div align="center">

  <img src="assets/logo.png" alt="Ports-Games Logo" width="140" height="140" />

  # Ports-Games Launcher
  
  **Catálogo inteligente, gestor y lanzador de ports de juegos, descompilaciones y proyectos comunitarios.**  
  *Smart catalog, manager, and launcher for game ports, decompilations, and community projects.*

  [![Version](https://img.shields.io/badge/version-1.0.0-emerald?style=for-the-badge)](https://github.com/nycrk/ports-games-launcher/releases)
  [![Platform](https://img.shields.io/badge/platform-Windows%20x64-blue?style=for-the-badge&logo=windows)](https://github.com/nycrk/ports-games-launcher/releases)
  [![Package](https://img.shields.io/badge/download-Portable%20ZIP-orange?style=for-the-badge&logo=archive)](https://github.com/nycrk/ports-games-launcher/releases/download/v1.0.0/Game-Ports-Portable-1.0.0-win-x64.zip)
  [![Website](https://img.shields.io/badge/Web-ports--games.com-cyan?style=for-the-badge&logo=google-chrome)](https://ports-games.com)

  <br />

  [🌐 Sitio Web Oficial](https://ports-games.com) • [📥 Descargar Launcher Portable](#-descargas-y-uso-rápido) • [🚀 Características](#-características-principales) • [⚖️ Aviso Legal](#-aviso-legal-y-filosofía-del-proyecto)

</div>

---

## 📖 Acerca del Proyecto

**Ports-Games Launcher** es una aplicación de escritorio nativa para Windows (x64) diseñada para descubrir, organizar y ejecutar ports comunitarios, reimplementaciones de motores clásicos y descompilaciones de videojuegos en un solo lugar.

Mantenemos nuestra información y base de datos actualizada periódicamente con los ports y herramientas más recientes de la comunidad, permitiendo vincular instalaciones locales, configurar archivos de tus copias legítimas y gestionar mods de forma segura y centralizada.

Visita nuestra plataforma web oficial: **[https://ports-games.com](https://ports-games.com)**

---

## 📥 Descargas y Uso Rápido

El launcher se distribuye como un paquete **100% portable y autocontenido**. No requiere instalación ni tener .NET previamente instalado en Windows.

### Enlaces de Descarga:
* 🚀 **[Descarga Directa: Game-Ports-Portable-1.0.0-win-x64.zip (v1.0.0)](https://github.com/nycrk/ports-games-launcher/releases/download/v1.0.0/Game-Ports-Portable-1.0.0-win-x64.zip)** *(57.5 MB)*
* 📦 **[Ver todas las versiones en GitHub Releases](https://github.com/nycrk/ports-games-launcher/releases)**
* 🌐 **[Descargar desde la Web Oficial (ports-games.com)](https://ports-games.com)**

### Instrucciones:
1. Descarga el archivo `.zip`.
2. Descomprímelo en cualquier carpeta de tu preferencia (ejemplo: `C:\Juegos\Ports-Games`).
3. Ejecuta `GamePorts.exe` y ¡listo para jugar!

---

## ✨ Características Principales

* 🎮 **Catálogo Inteligente**: Cientos de proyectos clasificados por consola/origen (N64, PS1, Xbox, Saturn, PC, Arcade, etc.) y plataforma de ejecución.
* 🔐 **Seguridad Criptográfica**: Catálogo cifrado con **AES-256-GCM** y firmado digitalmente mediante **ECDSA P-256 (SHA-256)** para garantizar su integridad.
* ⚡ **Alto Rendimiento**: Binario autocontenido optimizado con **ReadyToRun (R2R)** y bajo consumo de memoria RAM.
* 🌍 **Multilenguaje en Caliente**: Conmutación instantánea entre **Español** e **Inglés** en toda la interfaz sin necesidad de reiniciar el launcher.
* 📦 **Gestión de Datos y Extracción de ISOs**:
  - Detección guiada de archivos requeridos.
  - Integración con utilidad segura de extracción de ISOs de Xbox (`extract-xiso`).
  - Vinculación de ejecutables locales en un clic.
* 🧩 **Gestor de Mods Integrado**: Importa y activa o desactiva mods por carpetas o archivos sin alterar la instalación original.
* 🎨 **Personalización Visual**:
  - Modo Oscuro / Claro.
  - Color de acento personalizable con paleta visual y código HEX.
  - Formato de tarjetas (Horizontal clásico o Vertical estilo portada).
  - Vista de Tarjetas o Vista de Tabla con metadatos técnicos.

---

## 📁 Contenido del Paquete Portable

El archivo comprimido oficial incluye exclusivamente los componentes legítimos necesarios para su ejecución en Windows x64:

| Archivo / Carpeta | Descripción |
| :--- | :--- |
| `GamePorts.exe` | Ejecutable principal optimizado con tecnología nativa x64 |
| `catalog.dat` | Catálogo base cifrado y validado con firma criptográfica |
| `logo.png` | Identidad visual e icono de alta resolución |
| `libSkiaSharp.dll` | Renderizado gráfico 2D acelerado |
| `libHarfBuzzSharp.dll` | Motor tipográfico y texto de alta nitidez |
| `av_libglesv2.dll` | Biblioteca de aceleración gráfica por hardware |
| `Tools/extract-xiso.exe` | Herramienta integrada para extracción de copias de seguridad ISO |
| `Tools/extract-xiso-LICENSE.txt` | Licencia de la herramienta auxiliar |

---

## ⚖️ Aviso Legal y Filosofía del Proyecto

> [!IMPORTANT]
> **Ports-Games no distribuye ROMs, imágenes de disco comerciales, assets propietarios ni material protegido por derechos de autor.**

* Este proyecto es un gestor de catálogo que facilita la conexión con los repositorios, releases y herramientas de los autores de la comunidad.
* Para los ports que requieren archivos del juego original (música, texturas, modelos, niveles), el usuario debe poseer una copia legítima del videojuego y suministrar sus propios archivos mediante los métodos de extracción y vinculación soportados.

---

## 🌐 Enlaces y Comunidad

* **Sitio Web Oficial**: [https://ports-games.com](https://ports-games.com)
* **Reporte de Problemas o Sugerencias**: [GitHub Issues](https://github.com/nycrk/ports-games-launcher/issues)
* **Comunidad**: Hecho por y para la comunidad de entusiastas de los ports de videojuegos.
