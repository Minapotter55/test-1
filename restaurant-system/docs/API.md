# توثيق الـ API

كل الطلبات بتاخد وترجع JSON. كل المسارات (ماعدا `/api/public/*` و `/api/auth/login`) محتاجة الهيدر:
```
Authorization: Bearer <token>
```
الأخطاء بترجع بالشكل `{ "error": "رسالة" }` مع كود HTTP مناسب (400 / 401 / 403 / 404).

## تسجيل الدخول
| Method | Path | Body | الوصف |
|---|---|---|---|
| POST | `/api/auth/login` | `{ username, password }` | يرجع `{ token, user }` |
| GET | `/api/auth/me` | | المستخدم الحالي وصلاحياته |
| POST | `/api/auth/change-password` | `{ current_password, new_password }` | |

## عام (بدون تسجيل دخول)
| GET | `/api/public/info` | اسم المطعم والعملة |
|---|---|---|
| GET | `/api/public/track/:token` | حالة الطلب للعميل (`track_token` من بيانات الطلب) |

## الطلبات `orders.*`
| Method | Path | الصلاحية | الوصف |
|---|---|---|---|
| GET | `/api/orders` | حسب النطاق | فلاتر: `active=1`, `status=new,ready`, `branch_id`, `type`, `from`, `to` (YYYY-MM-DD), `q`, `mine=1`, `limit`, `offset` ← `{ rows, total }` |
| GET | `/api/orders/:id` | حسب النطاق | الطلب + `items` + `history` |
| POST | `/api/orders` | `orders.create` | طلب جديد (تحت) |
| PATCH | `/api/orders/:id/status` | `orders.update_status` / `orders.cancel` / الطيار | `{ status, note }` - الإلغاء لازم `note` |
| PATCH | `/api/orders/:id/driver` | `orders.assign_driver` | `{ driver_id }` أو `null` |
| PATCH | `/api/orders/:id/branch` | `orders.transfer` | `{ branch_id, note }` |

**النطاق:** `orders.view_all` يشوف كله، `orders.view_branch` يشوف فرعه، `orders.delivery` يشوف المسند له، `orders.create` يشوف اللي سجله.

**طلب جديد:**
```json
{
  "branch_id": 1,
  "type": "delivery",
  "payment_method": "cash",
  "discount": 0,
  "notes": "",
  "customer": { "name": "محمد", "phone": "01012345678" },
  "address": { "area": "المعادي", "address": "شارع 9", "landmark": "" },
  "items": [ { "item_id": 3, "qty": 2, "notes": "من غير بصل" } ]
}
```
- `type`: `delivery` | `pickup` | `dine_in`
- `payment_method`: `cash` | `card` | `online` | `wallet`
- `address`: عنوان جديد، أو `{ "id": 5 }` لعنوان محفوظ. مطلوب للتوصيل بس.
- الأسعار بتتحسب من السيرفر. العميل بيتسجل/يتحدث تلقائياً برقم الموبايل.

**الحالات:** `new` ← `accepted` ← `preparing` ← `ready` ← `out_for_delivery` (توصيل بس) ← `delivered`، أو `cancelled`.

## العملاء
| Method | Path | الوصف |
|---|---|---|
| GET | `/api/customers?q=` | بحث |
| GET | `/api/customers/lookup?phone=` | العميل بالرقم + عناوينه + آخر طلباته (أو `null`) |
| GET | `/api/customers/:id` | |
| POST | `/api/customers` | `{ name, phone, phone2, notes, address? }` |
| PUT | `/api/customers/:id` | |
| DELETE | `/api/customers/:id` | |
| POST | `/api/customers/:id/addresses` | `{ label, area, address, landmark }` |
| PUT / DELETE | `/api/customers/addresses/:aid` | |

## المنيو
| Method | Path | الوصف |
|---|---|---|
| GET | `/api/menu` | `{ categories, items }` |
| POST / PUT / DELETE | `/api/menu/categories[/:id]` | `{ name, sort_order, is_active }` |
| POST / PUT / DELETE | `/api/menu/items[/:id]` | `{ category_id, name, description, price, is_available, sort_order, image_url, image_data? }` (`image_data` = صورة data URL) |
| PATCH | `/api/menu/items/:id/availability` | `{ is_available }` |

## الفروع والمستخدمين والأدوار
| Method | Path | الوصف |
|---|---|---|
| GET / POST / PUT / DELETE | `/api/branches[/:id]` | `{ name, address, phone, delivery_fee, is_active }` |
| GET / POST / PUT / DELETE | `/api/users[/:id]` | `{ name, username, password, role_id, branch_id, phone, is_active }` |
| GET | `/api/users/drivers` | الطيارين المتاحين |
| GET / POST / PUT / DELETE | `/api/roles[/:id]` | `{ name, permissions: [] }` - `GET` بيرجع كمان قائمة كل الصلاحيات |

## أخرى
| GET | `/api/dashboard?from=&to=&branch_id=` | إحصائيات لوحة التحكم |
|---|---|---|
| GET / PUT | `/api/settings` | `restaurant_name, currency, restaurant_phone, receipt_footer` |
| GET | `/api/meta` | الحالات وأنواع الطلبات وطرق الدفع والصلاحيات بأسمائها |

## الإشعارات اللحظية (Socket.IO)
```js
const socket = io('http://server:3000', { auth: { token } });
socket.on('order:new', (order) => {});      // طلب جديد في نطاقك
socket.on('order:updated', (order) => {});  // تغيير حالة/طيار/فرع
socket.on('menu:changed', () => {});
socket.on('branches:changed', () => {});
socket.on('settings:changed', (settings) => {});
```
السيرفر بيبعت حدث الطلب للفرع بتاعه، واللي معاهم `orders.view_all`، والطيار المسند، واللي سجل الطلب بس.
