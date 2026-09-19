-- 测试用户数据生成脚本
-- 生成20个测试用户，用于开发和测试环境
-- 注意：此脚本适用于MySQL 8.0+

-- 设置字符集
SET NAMES utf8mb4;

-- 禁用外键检查（如果需要）
SET FOREIGN_KEY_CHECKS = 0;

-- 清空现有测试数据（谨慎使用）
-- DELETE FROM users WHERE id BETWEEN 100000 AND 100019;

-- 生成20个测试用户
INSERT INTO users (id, phone, email, password_hash, nickname, avatar, bio, zg_id, gender, birthday, school, tags_json, created_at, updated_at) VALUES
-- 用户1 - 张三
(100000, '13800138000', 'zhangsan@example.com', '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewdBPj/RK.PZvO.S', '张三', 'https://static.zhiguang.cn/avatar_1.jpg', '热爱编程的软件工程师', 'ZG000001', 'MALE', '1995-03-15', '清华大学', '["技术", "编程", "开源"]', NOW(), NOW()),

-- 用户2 - 李四
(100001, '13800138001', 'lisi@example.com', '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewdBPj/RK.PZvO.S', '李四', 'https://static.zhiguang.cn/avatar_2.jpg', '产品经理，专注于用户体验设计', 'ZG000002', 'FEMALE', '1993-07-22', '北京大学', '["产品", "设计", "用户体验"]', NOW(), NOW()),

-- 用户3 - 王五
(100002, '13800138002', 'wangwu@example.com', '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewdBPj/RK.PZvO.S', '王五', 'https://static.zhiguang.cn/avatar_3.jpg', '数据科学家，擅长机器学习算法', 'ZG000003', 'MALE', '1992-11-08', '上海交通大学', '["数据科学", "机器学习", "AI"]', NOW(), NOW()),

-- 用户4 - 赵六
(100003, '13800138003', 'zhaoliu@example.com', '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewdBPj/RK.PZvO.S', '赵六', 'https://static.zhiguang.cn/avatar_4.jpg', '前端开发工程师，React专家', 'ZG000004', 'FEMALE', '1994-05-30', '浙江大学', '["前端", "React", "JavaScript"]', NOW(), NOW()),

-- 用户5 - 钱七
(100004, '13800138004', 'qianqi@example.com', '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewdBPj/RK.PZvO.S', '钱七', 'https://static.zhiguang.cn/avatar_5.jpg', '后端架构师，微服务架构专家', 'ZG000005', 'MALE', '1990-09-12', '华中科技大学', '["后端", "架构", "微服务"]', NOW(), NOW()),

-- 用户6 - 孙八
(100005, '13800138005', 'sunba@example.com', '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewdBPj/RK.PZvO.S', '孙八', 'https://static.zhiguang.cn/avatar_6.jpg', 'UI设计师，专注移动端设计', 'ZG000006', 'FEMALE', '1996-01-25', '四川大学', '["UI设计", "移动端", "视觉设计"]', NOW(), NOW()),

-- 用户7 - 周九
(100006, '13800138006', 'zhoujiu@example.com', '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewdBPj/RK.PZvO.S', '周九', 'https://static.zhiguang.cn/avatar_7.jpg', 'DevOps工程师，容器化部署专家', 'ZG000007', 'MALE', '1991-12-03', '西安交通大学', '["DevOps", "Docker", "Kubernetes"]', NOW(), NOW()),

-- 用户8 - 吴十
(100007, '13800138007', 'wushi@example.com', '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewdBPj/RK.PZvO.S', '吴十', 'https://static.zhiguang.cn/avatar_8.jpg', '测试工程师，自动化测试专家', 'ZG000008', 'FEMALE', '1993-04-18', '中山大学', '["测试", "自动化", "质量保证"]', NOW(), NOW()),

-- 用户9 - 郑十一
(100008, '13800138008', 'zhengshiyi@example.com', '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewdBPj/RK.PZvO.S', '郑十一', 'https://static.zhiguang.cn/avatar_9.jpg', '安全工程师，网络安全专家', 'ZG000009', 'MALE', '1989-08-14', '北京航空航天大学', '["安全", "网络安全", "渗透测试"]', NOW(), NOW()),

-- 用户10 - 王十二
(100009, '13800138009', 'wangshier@example.com', '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewdBPj/RK.PZvO.S', '王十二', 'https://static.zhiguang.cn/avatar_10.jpg', '项目经理，敏捷开发实践者', 'ZG000010', 'FEMALE', '1988-06-27', '复旦大学', '["项目管理", "敏捷", "Scrum"]', NOW(), NOW()),

-- 用户11 - 李十三
(100010, '13800138010', 'lishisan@example.com', '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewdBPj/RK.PZvO.S', '李十三', 'https://static.zhiguang.cn/avatar_11.jpg', '移动开发工程师，iOS专家', 'ZG000011', 'MALE', '1994-02-09', '哈尔滨工业大学', '["移动开发", "iOS", "Swift"]', NOW(), NOW()),

-- 用户12 - 张十四
(100011, '13800138011', 'zhangshisi@example.com', '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewdBPj/RK.PZvO.S', '张十四', 'https://static.zhiguang.cn/avatar_12.jpg', '安卓开发工程师，Kotlin爱好者', 'ZG000012', 'FEMALE', '1995-10-16', '中南大学', '["安卓", "Kotlin", "移动开发"]', NOW(), NOW()),

-- 用户13 - 刘十五
(100012, '13800138012', 'liushiwu@example.com', '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewdBPj/RK.PZvO.S', '刘十五', 'https://static.zhiguang.cn/avatar_13.jpg', '数据库管理员，MySQL专家', 'ZG000013', 'MALE', '1990-11-23', '南京大学', '["数据库", "MySQL", "DBA"]', NOW(), NOW()),

-- 用户14 - 陈十六
(100013, '13800138013', 'chenshiliu@example.com', '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewdBPj/RK.PZvO.S', '陈十六', 'https://static.zhiguang.cn/avatar_14.jpg', '运维工程师，Linux系统专家', 'ZG000014', 'FEMALE', '1992-07-07', '厦门大学', '["运维", "Linux", "系统管理"]', NOW(), NOW()),

-- 用户15 - 杨十七
(100014, '13800138014', 'yangshiqi@example.com', '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewdBPj/RK.PZvO.S', '杨十七', 'https://static.zhiguang.cn/avatar_15.jpg', '算法工程师，竞赛金牌获得者', 'ZG000015', 'MALE', '1996-03-31', '东南大学', '["算法", "竞赛", "数学"]', NOW(), NOW()),

-- 用户16 - 黄十八
(100015, '13800138015', 'huangshiba@example.com', '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewdBPj/RK.PZvO.S', '黄十八', 'https://static.zhiguang.cn/avatar_16.jpg', '产品经理实习生，刚毕业的新人', 'ZG000016', 'FEMALE', '1997-09-19', '北京理工大学', '["产品", "实习", "新人"]', NOW(), NOW()),

-- 用户17 - 赵十九
(100016, '13800138016', 'zhaoshijiu@example.com', '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewdBPj/RK.PZvO.S', '赵十九', 'https://static.zhiguang.cn/avatar_17.jpg', '前端实习生，Vue.js初学者', 'ZG000017', 'MALE', '1998-01-05', '大连理工大学', '["前端", "实习", "Vue.js"]', NOW(), NOW()),

-- 用户18 - 周二十
(100017, '13800138017', 'zhousher@example.com', '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewdBPj/RK.PZvO.S', '周二十', 'https://static.zhiguang.cn/avatar_18.jpg', '后端实习生，Spring Boot学习者', 'ZG000018', 'FEMALE', '1997-12-12', '华南理工大学', '["后端", "实习", "Spring Boot"]', NOW(), NOW()),

-- 用户19 - 吴二十一
(100018, '13800138018', 'wueryishi@example.com', '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewdBPj/RK.PZvO.S', '吴二十一', 'https://static.zhiguang.cn/avatar_19.jpg', '测试实习生，自动化测试入门者', 'ZG000019', 'MALE', '1998-04-28', '电子科技大学', '["测试", "实习", "自动化"]', NOW(), NOW()),

-- 用户20 - 郑二十二
(100019, '13800138019', 'zhengershi@example.com', '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewdBPj/RK.PZvO.S', '郑二十二', 'https://static.zhiguang.cn/avatar_20.jpg', '设计实习生，UI设计新手', 'ZG000020', 'FEMALE', '1998-08-03', '湖南大学', '["设计", "实习", "UI"]', NOW(), NOW());

-- 重新启用外键检查
SET FOREIGN_KEY_CHECKS = 1;

-- 验证数据插入
SELECT COUNT(*) as total_users FROM users WHERE id BETWEEN 100000 AND 100019;
SELECT id, nickname, email, phone, zg_id FROM users WHERE id BETWEEN 100000 AND 100019 ORDER BY id;

-- 如果需要生成关注关系数据，可以使用以下语句（示例）
/*
-- 生成一些测试的关注关系
INSERT INTO following (id, from_user_id, to_user_id, rel_status, created_at, updated_at) VALUES
(200000, 100000, 100001, 1, NOW(), NOW()),
(200001, 100000, 100002, 1, NOW(), NOW()),
(200002, 100001, 100000, 1, NOW(), NOW()),
(200003, 100002, 100000, 1, NOW(), NOW());

INSERT INTO follower (id, to_user_id, from_user_id, rel_status, created_at, updated_at) VALUES
(300000, 100001, 100000, 1, NOW(), NOW()),
(300001, 100002, 100000, 1, NOW(), NOW()),
(300002, 100000, 100001, 1, NOW(), NOW()),
(300003, 100000, 100002, 1, NOW(), NOW());
*/
