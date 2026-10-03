// كل الصلاحيات المتاحة في السيستم
const PERMISSIONS = {
  'dashboard.view': 'عرض لوحة التحكم والتقارير',
  'orders.create': 'تسجيل طلبات جديدة',
  'orders.view_all': 'عرض طلبات كل الفروع',
  'orders.view_branch': 'عرض طلبات الفرع بتاعه',
  'orders.update_status': 'تحديث حالة الطلب',
  'orders.cancel': 'إلغاء الطلبات',
  'orders.transfer': 'تحويل الطلب لفرع تاني',
  'orders.assign_driver': 'تعيين طيار للطلب',
  'orders.delivery': 'طيار توصيل (يشوف الطلبات المسندة له)',
  'customers.view': 'عرض العملاء',
  'customers.manage': 'إضافة وتعديل العملاء',
  'menu.manage': 'إدارة المنيو والأصناف والأسعار',
  'branches.manage': 'إدارة الفروع',
  'users.manage': 'إدارة المستخدمين والصلاحيات',
  'settings.manage': 'إعدادات السيستم',
};

const ALL_PERMISSIONS = Object.keys(PERMISSIONS);

// الأدوار الافتراضية اللي بتتعمل أول تشغيل
const DEFAULT_ROLES = [
  { key: 'admin', name: 'مدير عام', permissions: ALL_PERMISSIONS, is_system: 1 },
  {
    key: 'manager', name: 'مدير فرع', is_system: 0,
    permissions: ['dashboard.view', 'orders.create', 'orders.view_branch', 'orders.update_status',
      'orders.cancel', 'orders.assign_driver', 'customers.view', 'customers.manage'],
  },
  {
    key: 'call_center', name: 'كول سنتر', is_system: 0,
    permissions: ['orders.create', 'orders.view_all', 'orders.transfer', 'orders.cancel',
      'customers.view', 'customers.manage'],
  },
  {
    key: 'branch_staff', name: 'موظف فرع / مطبخ', is_system: 0,
    permissions: ['orders.view_branch', 'orders.update_status'],
  },
  { key: 'driver', name: 'طيار توصيل', is_system: 0, permissions: ['orders.delivery'] },
];

// حالات الطلب بالترتيب
const STATUSES = ['new', 'accepted', 'preparing', 'ready', 'out_for_delivery', 'delivered', 'cancelled'];
const STATUS_LABELS = {
  new: 'جديد',
  accepted: 'تم القبول',
  preparing: 'جاري التحضير',
  ready: 'جاهز',
  out_for_delivery: 'مع الطيار',
  delivered: 'تم التسليم',
  cancelled: 'ملغي',
};
const FINAL_STATUSES = ['delivered', 'cancelled'];
const ACTIVE_STATUSES = STATUSES.filter((s) => !FINAL_STATUSES.includes(s));

const ORDER_TYPES = { delivery: 'توصيل', pickup: 'استلام من الفرع', dine_in: 'صالة' };
const PAYMENT_METHODS = { cash: 'كاش', card: 'فيزا', online: 'دفع أونلاين', wallet: 'محفظة إلكترونية' };

module.exports = {
  PERMISSIONS, ALL_PERMISSIONS, DEFAULT_ROLES,
  STATUSES, STATUS_LABELS, FINAL_STATUSES, ACTIVE_STATUSES,
  ORDER_TYPES, PAYMENT_METHODS,
};
