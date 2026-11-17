ТГ: https://t.me/CMEPT0HOCHbIU

OPTIMIZE-NETWORKING.reg + NETWORK-TWEAKS.ps1 - Оптимизация всех настроек сетевого адаптера
DISABLE-POWERSAVING.reg - Отключение всех функций энергосбережения сетевого адаптера
CHECK-POWER-MANAGEMENT.ps1 - Проверка статуса некоторых функций энергосбережения сетевого адаптера
find_network_adapter_path.bat - Позволяет узнать путь до настроек сетевого адаптера

ВАЖНО В OPTIMIZE-NETWORKING.reg и DISABLE-POWERSAVING.reg поставить верный путь, который вы получили с find_network_adapter_path.bat, то есть если find_network_adapter_path.bat выдаёт: HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Class\{4D36E972-E325-11CE-BFC1-08002bE10318}\0010, то измените HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Class\{4D36E972-E325-11CE-BFC1-08002bE10318}\0001 в reg файлах на HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Class\{4D36E972-E325-11CE-BFC1-08002bE10318}\0010, а после этого примените

Powershell(ps1)-скрипты запускайте через батники (RUN)

Настройки актуальны для всех сетевых адаптеров (Intel/Realtek/Mellanox и так далее)