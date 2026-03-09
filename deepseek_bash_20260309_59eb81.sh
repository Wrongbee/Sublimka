#!/bin/bash

# Скрипт установки Nginx с HTTPS на порту 443 для сайта-заглушки
# Не вмешивается в работу 3x-ui, но предупреждает о конфликте портов

set -e  # остановка при ошибке

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Начинаем установку Nginx для сайта-заглушки на порт 443${NC}"

# 1. Проверка, не занят ли порт 443 процессом 3x-ui (xray)
echo -e "${YELLOW}🔍 Проверяем, кто слушает порт 443...${NC}"
if ss -tlnp | grep -q ':443'; then
    PROCESS=$(ss -tlnp | grep ':443' | awk '{print $7}' | cut -d'"' -f2 | head -n1)
    echo -e "${RED}❌ Порт 443 уже используется процессом: $PROCESS${NC}"
    echo -e "${YELLOW}Возможно, это 3x-ui (xray). Для работы сайта на 443 необходимо перенастроить 3x-ui на другой порт.${NC}"
    echo -e "Например, можно изменить порты всех inbounds в панели 3x-ui на 8443 (или любой другой)."
    echo -e "После этого запустите скрипт заново."
    exit 1
else
    echo -e "${GREEN}✅ Порт 443 свободен. Продолжаем.${NC}"
fi

# 2. Установка Nginx (если не установлен)
if ! command -v nginx &> /dev/null; then
    echo -e "${YELLOW}📦 Устанавливаем Nginx...${NC}"
    sudo apt update
    sudo apt install nginx -y
else
    echo -e "${GREEN}✅ Nginx уже установлен.${NC}"
fi

# 3. Создание папки для сайта
SITE_DIR="/var/www/landing"
echo -e "${YELLOW}📁 Создаём папку сайта: $SITE_DIR${NC}"
sudo mkdir -p "$SITE_DIR"
sudo chown -R www-data:www-data "$SITE_DIR"

# 4. Если в папке нет index.html, создаём простой (можно заменить потом)
if [ ! -f "$SITE_DIR/index.html" ]; then
    echo -e "${YELLOW}🌐 Создаём простой index.html (вы сможете заменить его позже)${NC}"
    sudo tee "$SITE_DIR/index.html" > /dev/null <<'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <title>Сайт находится на обслуживании</title>
    <style>
        body { font-family: Arial; text-align: center; padding: 50px; background: #f5f5f5; }
        h1 { color: #333; }
    </style>
</head>
<body>
    <h1>🚧 Ведутся технические работы</h1>
    <p>Сайт временно недоступен. Приносим извинения за неудобства.</p>
</body>
</html>
EOF
else
    echo -e "${GREEN}✅ Файл index.html уже существует в $SITE_DIR, оставляем как есть.${NC}"
fi

# 5. Генерация самоподписного SSL-сертификата (для HTTPS)
SSL_DIR="/etc/nginx/ssl/landing"
echo -e "${YELLOW}🔐 Создаём самоподписной SSL-сертификат для сайта...${NC}"
sudo mkdir -p "$SSL_DIR"
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "$SSL_DIR/privkey.pem" \
    -out "$SSL_DIR/fullchain.pem" \
    -subj "/C=RU/ST=Moscow/L=Moscow/O=MyOrg/CN=localhost" 2>/dev/null

# 6. Настройка конфигурации Nginx для HTTPS на порту 443
echo -e "${YELLOW}⚙️ Настраиваем виртуальный хост Nginx...${NC}"
sudo tee /etc/nginx/sites-available/landing > /dev/null <<EOF
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    
    ssl_certificate $SSL_DIR/fullchain.pem;
    ssl_certificate_key $SSL_DIR/privkey.pem;
    
    root $SITE_DIR;
    index index.html index.htm;
    
    server_name _;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

# Активируем сайт и удаляем дефолтный (если есть)
sudo ln -sf /etc/nginx/sites-available/landing /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# 7. Проверка конфигурации и перезапуск Nginx
echo -e "${YELLOW}🔄 Проверяем конфигурацию и перезапускаем Nginx...${NC}"
sudo nginx -t && sudo systemctl restart nginx

# 8. Открываем порт 443 в firewall (если используется ufw)
if command -v ufw &> /dev/null; then
    echo -e "${YELLOW}🛡️ Открываем порт 443 в UFW...${NC}"
    sudo ufw allow 443/tcp comment 'HTTPS landing page' 2>/dev/null || echo "   UFW уже разрешает порт 443 или не активен."
fi

# 9. Итог
echo -e "${GREEN}✅ Готово! Сайт-заглушка установлен и доступен по HTTPS на порту 443.${NC}"
IP=$(curl -s ifconfig.me)
echo -e "${GREEN}   Откройте в браузере: https://$IP${NC}"
echo -e "${YELLOW}⚠️  Важное предупреждение:${NC}"
echo -e "   Теперь порт 443 занят Nginx. Чтобы 3x-ui продолжал работать, необходимо:"
echo -e "   1. Зайти в панель 3x-ui."
echo -e "   2. Для каждого inbound'а (входящего подключения) изменить порт на другой (например, 8443)."
echo -e "   3. Убедиться, что в поле 'Listen IP' указано 0.0.0.0 (или оставлено пустым), чтобы слушать внешние подключения."
echo -e "   4. Перезапустить 3x-ui."
echo -e "   После этого клиенты VPN должны подключаться к новому порту (например, 8443)."
echo -e ""
echo -e "${YELLOW}💡 Если вы хотите, чтобы и сайт, и VPN работали на одном порту 443, потребуется reverse proxy. Тогда напишите мне — сделаем другой скрипт.${NC}"