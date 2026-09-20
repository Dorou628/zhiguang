-- Local-only demo account; Docker ports are bound to loopback.
-- Email: demo@example.com   Password: DemoPass123!
SET NAMES utf8mb4;
INSERT INTO users (id, email, password_hash, nickname, bio, zg_id, created_at, updated_at)
VALUES (100020, 'demo@example.com', '$2a$12$xvw6bFPxQzEpqS.Ki/kKTux18YGlV/hxfaETs.lHiv58faXZSgx7W',
        '本地演示用户', '一键启动包的本地演示账号', 'ZGDEMO001', NOW(), NOW())
ON DUPLICATE KEY UPDATE nickname=VALUES(nickname);
