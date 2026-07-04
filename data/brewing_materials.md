# 怪物偏好与酿酒素材关联数据库

在『灯火酒馆』中，怪物客人的生态学极其严谨。**怪物掉落的两种素材，其内含风味必然是该种怪物本身所厌恶的**（这代表了它们在生物新陈代谢中无法吸收、最终囤积并在体表排泄累积的杂质元素）。

这一机制创造了绝佳的策略深度：**绝对不要用怪物掉落的本源素材去酿制给该怪物饮用的酒，否则会精准踩雷！** 

## 1. 怪物偏好与掉落对照表 (Monster Preferences & Drops)

| 怪物 ID | 怪物名称 | 喜好风味 (Liked) | 讨厌风味 (Disliked) | 对应掉落素材 (1) [包含讨厌风味] | 对应掉落素材 (2) [包含讨厌风味] |
| --- | --- | --- | --- | --- | --- |
| `goblin` | **哥布林** | sweet, umami | bitter, salty | `goblin_ear` | `goblin_tooth` |
| `spider` | **巨型蜘蛛** | gaminess, salty | spicy, sweet | `spider_poison_sac` | `spider_web` |
| `slime` | **史莱姆** | sour, sweet | salty, earthy | `slime_core` | `slime_jelly` |
| `bat` | **洞穴蝙蝠** | bitter, sour | fresh, floral | `bat_wing` | `bat_guano` |
| `skeleton` | **骷髅兵** | earthy, dry | umami, sweet | `skeleton_dust` | `fossil_bone` |
| `rat` | **巨鼠** | gaminess, earthy | sour, spicy | `giant_rat_tail` | `rat_whisker` |
| `imp` | **小恶魔** | spicy, smoky | fresh, sour | `imp_horn_dust` | `imp_wing_ash` |
| `troll` | **巨魔** | salty, metallic | sweet, earthy | `troll_blood` | `troll_skin` |
| `zombie` | **僵尸** | pungent, bitter | floral, sweet | `zombie_flesh` | `zombie_nail` |
| `harpy` | **哈比** | floral, fresh | gaminess, bitter | `harpy_feather` | `harpy_talon` |

## 2. 酿酒素材数据库 (35种素材总览)

包含 15 种通过地图直接采集获得的素材，以及上述 20 种怪物掉落素材。

| ID | 素材名称 | 来源分类 | 归属怪物 | 风味及点数 | 描述 |
| --- | --- | --- | --- | --- | --- |
| `wild_glowcap` | **野生荧光菇** | 直接采集 | `N/A` | earthy: 3, bitter: 1 | 在黑暗洞穴中散发微光的菌类，能给酒液带来奇妙的视觉效果。 |
| `frost_berry` | **霜冻浆果** | 直接采集 | `N/A` | sour: 2, sweet: 4 | 生长在寒冷高地的浆果，能让饮品保持冰凉的口感。 |
| `fire_bloom` | **烈焰花瓣** | 直接采集 | `N/A` | spicy: 5 | 蕴含微弱火元素的红色花朵，能让酒口感发热。 |
| `cave_lichen` | **洞穴苔藓** | 直接采集 | `N/A` | salty: 2, earthy: 2 | 附着在阴湿岩石上的地衣，常用于低成本酿造。 |
| `honeycomb` | **野生蜂巢** | 直接采集 | `N/A` | sweet: 5, floral: 2 | 森林里野生蜂巢，极度甜美。 |
| `sweet_grass` | **甜心草** | 直接采集 | `N/A` | sweet: 2, fresh: 3 | 原野上常见的多汁草本，适合作为基础甜味调和。 |
| `bitter_root` | **苦艾根** | 直接采集 | `N/A` | bitter: 5 | 极度苦涩的植物根茎，是某些重口味客人的最爱。 |
| `mountain_barley` | **高山大麦** | 直接采集 | `N/A` | earthy: 4 | 酿造烈性麦芽酒的核心谷物。 |
| `witch_plum` | **女巫李** | 直接采集 | `N/A` | sour: 4, sweet: 1 | 带有神秘紫色光泽的水果，酸味浓郁。 |
| `shadow_lotus` | **暗影莲花** | 直接采集 | `N/A` | umami: 3, floral: 3 | 只在夜间盛开的黑色莲花。 |
| `sunflower_seed` | **向日葵籽** | 直接采集 | `N/A` | nutty: 3, sweet: 1 | 炒熟后能提供浓郁的油脂和坚果香气。 |
| `ironwood_bark` | **铁木树皮** | 直接采集 | `N/A` | woody: 4, bitter: 2 | 质地坚硬的树皮，能带给酒桶陈酿般的厚重木香。 |
| `amber_resin` | **琥珀树树脂** | 直接采集 | `N/A` | sweet: 3, smoky: 2 | 凝固的树脂，带有一股独特的松脂与烟熏风味。 |
| `acid_grape` | **酸腺葡萄** | 直接采集 | `N/A` | sour: 5 | 酸度惊人的野生葡萄，需要大量甜味中和。 |
| `rock_salt` | **岩盐结晶** | 直接采集 | `N/A` | salty: 5 | 矿洞深处的盐结晶，可以强化其他风味的表达。 |
| `goblin_ear` | **哥布林耳尖** | 怪物掉落 | `goblin` | bitter: 3 | 哥布林囤积苦涩味的耳朵，风味干涩。 |
| `goblin_tooth` | **哥布林犬齿** | 怪物掉落 | `goblin` | salty: 2 | 钙质结晶，带有微量的咸涩咸风味。 |
| `spider_poison_sac` | **蜘蛛毒囊** | 怪物掉落 | `spider` | spicy: 4 | 充满神经毒素，入口带强烈的辛辣刺痛感。 |
| `spider_web` | **粘稠蜘蛛丝** | 怪物掉落 | `spider` | sweet: 2 | 蛛丝提取的糖蛋白，具有出奇的粘稠甜味。 |
| `slime_core` | **史莱姆核心** | 怪物掉落 | `slime` | salty: 3 | 凝结的无机盐核心，风味极咸。 |
| `slime_jelly` | **史莱姆凝胶** | 怪物掉落 | `slime` | earthy: 2 | 胶质外壳，带有潮湿地底的泥土腥香。 |
| `bat_wing` | **蝙蝠翅膀** | 怪物掉落 | `bat` | floral: 2 | 蝙蝠长期接触岩壁奇花，积攒了淡淡的花香。 |
| `bat_guano` | **蝙蝠粪便结晶** | 怪物掉落 | `bat` | fresh: 3 | 蝙蝠排泄出的精纯草本浓缩结晶，味道清香四溢。 |
| `skeleton_dust` | **白骨粉末** | 怪物掉落 | `skeleton` | sweet: 2 | 腐殖质脱水产生的甜味骨粉。 |
| `fossil_bone` | **古老遗骨** | 怪物掉落 | `skeleton` | umami: 3 | 深层化石，富含有机钙质鲜味。 |
| `giant_rat_tail` | **巨鼠尾巴** | 怪物掉落 | `rat` | sour: 3 | 巨鼠尾巴积累的酸性腺体分泌物，酸涩无比。 |
| `rat_whisker` | **巨鼠胡须** | 怪物掉落 | `rat` | spicy: 2 | 坚硬锋利的胡须，浸泡后释放刺鼻的辛辣感。 |
| `imp_horn_dust` | **小恶魔角粉** | 怪物掉落 | `imp` | sour: 3 | 恶魔尖角粉，具有极高浓度的酸性腐蚀风味。 |
| `imp_wing_ash` | **恶魔翅灰** | 怪物掉落 | `imp` | fresh: 3 | 恶魔拍打翅膀燃尽后的灰烬，带有一股冷冽的清凉感。 |
| `troll_blood` | **巨魔之血** | 怪物掉落 | `troll` | earthy: 4 | 巨魔再生能力来源，带有厚重的地底泥土芬芳。 |
| `troll_skin` | **巨魔厚皮** | 怪物掉落 | `troll` | sweet: 2 | 角质化厚皮，咀嚼后释放奇特的胶原蛋白甜味。 |
| `zombie_flesh` | **腐肉精华** | 怪物掉落 | `zombie` | floral: 3 | 虽然腐烂，却因为常年埋藏于墓地而散发浓郁的花香。 |
| `zombie_nail` | **僵尸指甲** | 怪物掉落 | `zombie` | sweet: 2 | 指甲盖内积蓄的古老酵糖，味道甘甜。 |
| `harpy_feather` | **哈比羽毛粉** | 怪物掉落 | `harpy` | bitter: 3 | 羽毛管腺体分泌的极度苦涩油脂，防风防雨。 |
| `harpy_talon` | **哈比尖爪** | 怪物掉落 | `harpy` | gaminess: 4 | 撕裂猎物后留下的、带浓重野兽膻腥气息的利爪。 |
