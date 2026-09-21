<?php
$settings = [
    'DB_NAME' => getenv('MYSQL_DATABASE'),
    'DB_USER' => getenv('MYSQL_USER'),
    'DB_HOST' => 'mariadb:3306',
    'DB_CHARSET' => 'utf8mb4',
    'DB_COLLATE' => '',
    'FORCE_SSL_ADMIN' => true,
    'DISALLOW_FILE_EDIT' => true,
    'DISALLOW_FILE_MODS' => true,
    'WP_AUTO_UPDATE_CORE' => false,
    'AUTOMATIC_UPDATER_DISABLED' => true,
    'WP_REDIS_HOST' => 'redis',
    'WP_REDIS_PORT' => 6379,
    'WP_REDIS_DATABASE' => 0,
    'WP_REDIS_PREFIX' => getenv('DOMAIN_NAME') . ':',
    'WP_REDIS_GRACEFUL' => true,
];
echo "<?php\n";
foreach ($settings as $key => $value) {
    echo 'define(' . var_export($key, true) . ', ' . var_export($value, true) . ");\n";
}
foreach (['AUTH_KEY', 'SECURE_AUTH_KEY', 'LOGGED_IN_KEY', 'NONCE_KEY', 'AUTH_SALT', 'SECURE_AUTH_SALT', 'LOGGED_IN_SALT', 'NONCE_SALT'] as $key) {
    echo 'define(' . var_export($key, true) . ', ' . var_export(bin2hex(random_bytes(32)), true) . ");\n";
}
echo <<<'CONFIG'
define('DB_PASSWORD', trim(file_get_contents('/run/php/db_password')));
define('WP_REDIS_PASSWORD', trim(file_get_contents('/run/php/redis_password')));
define('WP_REDIS_USERNAME', 'wordpress');
define('WP_REDIS_DISABLED', getenv('WP_REDIS_DISABLED') !== '0');
$table_prefix = 'wp_';
if (!defined('ABSPATH')) {
    define('ABSPATH', __DIR__ . '/');
}
require_once ABSPATH . 'wp-settings.php';
CONFIG;
