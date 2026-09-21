<?php
[$name, $role, $secretFile] = $args;
$user = get_user_by('login', $name);
$password = trim(file_get_contents($secretFile));
if (!$user || !wp_check_password($password, $user->user_pass, $user->ID) || !in_array($role, $user->roles, true)) {
    WP_CLI::error('WordPress account, role or secret does not match existing data.');
}
