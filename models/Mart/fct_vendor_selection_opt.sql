with source as (

    select * from {{ ref('int_vendor_selection__vendor_pricing_performance_manager') }}

),

reconstruct as (

    select
        * except (valid_from, product_rank)
    from source
    where CURRENT_DATE() >= valid_from 
    and CURRENT_DATE() < valid_to

)

select * from reconstruct
