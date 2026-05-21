with source as (

    select * from {{ ref('int_vendor_selection__vendor_pricing_performance_manager') }}

),

reconstruct as (

    select
        * except (create_time, product_rank)
    from source
    qualify row_number() over (
        partition by country_code, vendor_id, product_id
        order by create_time desc
    ) = 1

)

select * from reconstruct
