select *
from {{ ref('int_vendor_selection__vendor_pricing_performance_manager') }}
where rate is null
   or rate <= 0
