CREATE OR REPLACE PACKAGE BODY HTM_QUERY_INTERFACE AS

  -- Constants for intersection status
  c_status_full_outside CONSTANT INTEGER := 0;
  c_status_full_inside CONSTANT INTEGER := 1;
  c_status_partial_intersect CONSTANT INTEGER := 2;
  
  c_epsilon CONSTANT NUMBER := 0.0000000001; -- For floating point comparisons in dot products

  -- Record types for query shape parameters
  TYPE type_circle_params IS RECORD (
    center_vec HTM_VECTOR,
    cos_radius NUMBER
  );

  TYPE type_hull_params IS RECORD (
    constraint_planes HTM_VERTEX_LIST -- List of normal vectors for the hull planes
  );

  -- Forward declaration of the recursive helper
  PROCEDURE intersect_node_recursive(
    node_id NUMBER,
    p_query_level NUMBER,
    p_circle_params type_circle_params,
    p_hull_params type_hull_params,
    p_is_circle_query BOOLEAN,
    current_results IN OUT NOCOPY HTM_ID_RANGE_LIST
  );

  -----------------------------------------------------------------------------
  -- Intersection Status Checkers
  -----------------------------------------------------------------------------
  FUNCTION check_triangle_circle_intersect_status(
    v0 HTM_VECTOR, v1 HTM_VECTOR, v2 HTM_VECTOR, -- Triangle vertices
    params type_circle_params
  ) RETURN INTEGER IS
    v_in_count INTEGER := 0;
    -- dot products for each vertex with circle center
    dot0 NUMBER;
    dot1 NUMBER;
    dot2 NUMBER;
  BEGIN
    dot0 := params.center_vec.dot_product(v0);
    dot1 := params.center_vec.dot_product(v1);
    dot2 := params.center_vec.dot_product(v2);

    IF dot0 >= params.cos_radius - c_epsilon THEN v_in_count := v_in_count + 1; END IF;
    IF dot1 >= params.cos_radius - c_epsilon THEN v_in_count := v_in_count + 1; END IF;
    IF dot2 >= params.cos_radius - c_epsilon THEN v_in_count := v_in_count + 1; END IF;

    IF v_in_count = 3 THEN
      RETURN c_status_full_inside;
    END IF;

    IF dot0 < params.cos_radius + c_epsilon AND 
       dot1 < params.cos_radius + c_epsilon AND 
       dot2 < params.cos_radius + c_epsilon THEN
        IF HTM_GEOMETRY_UTILS.is_inside_triangle(params.center_vec, v0, v1, v2, c_epsilon) THEN
            RETURN c_status_partial_intersect; 
        END IF;
        
        IF v_in_count = 0 THEN
            RETURN c_status_partial_intersect; 
        END IF;
    END IF;
    
    RETURN c_status_partial_intersect; 
  END check_triangle_circle_intersect_status;

  FUNCTION check_triangle_hull_intersect_status(
    tv0 HTM_VECTOR, tv1 HTM_VECTOR, tv2 HTM_VECTOR, -- Triangle vertices
    params type_hull_params
  ) RETURN INTEGER IS
    all_vertices_outside_one_constraint BOOLEAN := FALSE;
    is_fully_inside_all_constraints BOOLEAN := TRUE;
  BEGIN
    IF params.constraint_planes IS NULL OR params.constraint_planes.COUNT = 0 THEN
      RETURN c_status_partial_intersect; 
    END IF;

    FOR i IN 1 .. params.constraint_planes.COUNT LOOP
      DECLARE
        n_plane HTM_VECTOR := params.constraint_planes(i);
      BEGIN
        IF n_plane.dot_product(tv0) < -c_epsilon AND
           n_plane.dot_product(tv1) < -c_epsilon AND
           n_plane.dot_product(tv2) < -c_epsilon THEN
          all_vertices_outside_one_constraint := TRUE;
          EXIT; 
        END IF;
      END;
    END LOOP;

    IF all_vertices_outside_one_constraint THEN
      RETURN c_status_full_outside;
    END IF;

    FOR i IN 1 .. params.constraint_planes.COUNT LOOP
      DECLARE
        n_plane HTM_VECTOR := params.constraint_planes(i);
      BEGIN
        IF n_plane.dot_product(tv0) < -c_epsilon OR
           n_plane.dot_product(tv1) < -c_epsilon OR
           n_plane.dot_product(tv2) < -c_epsilon THEN
          is_fully_inside_all_constraints := FALSE;
          EXIT; 
        END IF;
      END;
    END LOOP;

    IF is_fully_inside_all_constraints THEN
      RETURN c_status_full_inside;
    END IF;

    RETURN c_status_partial_intersect;
  END check_triangle_hull_intersect_status;

  -----------------------------------------------------------------------------
  -- Recursive Intersection Logic
  -----------------------------------------------------------------------------
  PROCEDURE intersect_node_recursive(
    node_id NUMBER,
    p_query_level NUMBER,
    p_circle_params type_circle_params,
    p_hull_params type_hull_params,
    p_is_circle_query BOOLEAN,
    current_results IN OUT NOCOPY HTM_ID_RANGE_LIST
  ) IS
    v0 HTM_VECTOR;
    v1 HTM_VECTOR;
    v2 HTM_VECTOR;
    node_info HTM_NODE;
    node_status INTEGER;
    levels_to_descend INTEGER;
    range_low_id NUMBER;
    range_high_id NUMBER;
  BEGIN
    node_info := HTM_INDEX_CORE.get_node_info(node_id);

    IF node_info.level_num > p_query_level THEN
      RETURN; 
    END IF;

    HTM_INDEX_CORE.get_node_vertices(node_id, v0, v1, v2);

    IF p_is_circle_query THEN
      node_status := check_triangle_circle_intersect_status(v0, v1, v2, p_circle_params);
    ELSE
      node_status := check_triangle_hull_intersect_status(v0, v1, v2, p_hull_params);
    END IF;

    CASE node_status
      WHEN c_status_full_outside THEN
        RETURN; 

      WHEN c_status_full_inside THEN
        IF node_info.level_num = p_query_level THEN
          HTM_RANGE_UTILS.add_range(current_results, node_id, node_id);
        ELSE 
          levels_to_descend := p_query_level - node_info.level_num;
          range_low_id := node_id * POWER(4, levels_to_descend);
          range_high_id := (node_id + 1) * POWER(4, levels_to_descend) - 1;
          HTM_RANGE_UTILS.add_range(current_results, range_low_id, range_high_id);
        END IF;

      WHEN c_status_partial_intersect THEN
        IF node_info.level_num = p_query_level THEN
          HTM_RANGE_UTILS.add_range(current_results, node_id, node_id);
        ELSIF node_info.level_num < p_query_level THEN
          IF node_info.children_ids IS NOT NULL AND node_info.children_ids.COUNT = 4 THEN
             FOR i IN 1 .. node_info.children_ids.COUNT LOOP
                intersect_node_recursive(node_info.children_ids(i), p_query_level, p_circle_params, p_hull_params, p_is_circle_query, current_results);
             END LOOP;
          ELSIF node_info.is_leaf = 0 THEN 
             FOR child_idx IN 0 .. 3 LOOP
                intersect_node_recursive((node_id * 4) + child_idx, p_query_level, p_circle_params, p_hull_params, p_is_circle_query, current_results);
             END LOOP;
          ELSE 
             FOR child_idx IN 0 .. 3 LOOP
                intersect_node_recursive((node_id * 4) + child_idx, p_query_level, p_circle_params, p_hull_params, p_is_circle_query, current_results);
             END LOOP;
          END IF;
        END IF; 
    END CASE;

  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Error in intersect_node_recursive for node ' || node_id || ': ' || SQLERRM);
      RAISE;
  END intersect_node_recursive;

  -----------------------------------------------------------------------------
  -- Public Functions
  -----------------------------------------------------------------------------
  FUNCTION circle_region_intersect(
    center_ra NUMBER,
    center_dec NUMBER,
    radius_degrees NUMBER,
    query_level NUMBER
  ) RETURN HTM_ID_RANGE_LIST IS
    center_v HTM_VECTOR;
  BEGIN
    IF center_ra IS NULL OR center_dec IS NULL OR radius_degrees IS NULL OR query_level IS NULL THEN
        RAISE_APPLICATION_ERROR(-20200, 'Input parameters cannot be null for circle_region_intersect.');
    END IF;
    IF radius_degrees < 0 THEN
        RAISE_APPLICATION_ERROR(-20201, 'Radius cannot be negative.');
    END IF;
    IF query_level < 0 OR query_level > HTM_INDEX_CORE.g_max_query_level THEN
       RAISE_APPLICATION_ERROR(-20202, 'Query level is out of range.');
    END IF;

    center_v := HTM_VECTOR(center_ra, center_dec); 
    RETURN circle_region_intersect_cartesian(center_v, radius_degrees, query_level);
  END circle_region_intersect;

  FUNCTION circle_region_intersect_cartesian(
    center_vec HTM_VECTOR,
    radius_degrees NUMBER,
    query_level NUMBER
  ) RETURN HTM_ID_RANGE_LIST IS
    results HTM_ID_RANGE_LIST;
    params type_circle_params;
    root_nodes HTM_NUMBER_LIST := HTM_NUMBER_LIST(8,9,10,11,12,13,14,15); 
    temp_center_vec HTM_VECTOR := center_vec;
  BEGIN
    IF temp_center_vec IS NULL OR radius_degrees IS NULL OR query_level IS NULL THEN
        RAISE_APPLICATION_ERROR(-20210, 'Input parameters cannot be null for circle_region_intersect_cartesian.');
    END IF;
    IF radius_degrees < 0 THEN
        RAISE_APPLICATION_ERROR(-20211, 'Radius cannot be negative.');
    END IF;
    IF query_level < 0 OR query_level > HTM_INDEX_CORE.g_max_query_level THEN
       RAISE_APPLICATION_ERROR(-20212, 'Query level is out of range.');
    END IF;

    temp_center_vec.normalize(); 
    params.center_vec := temp_center_vec;
    params.cos_radius := COS(radius_degrees * HTM_GEOMETRY_UTILS.c_pi / 180.0);
    
    results := HTM_RANGE_UTILS.create_empty_range_list();

    FOR i IN 1 .. root_nodes.COUNT LOOP
      intersect_node_recursive(root_nodes(i), query_level, params, NULL, TRUE, results);
    END LOOP;

    HTM_RANGE_UTILS.merge_ranges(results); 
    RETURN results;
  END circle_region_intersect_cartesian;

  FUNCTION convex_hull_intersect(
    vertices_ra_dec HTM_VERTEX_LIST,
    query_level NUMBER
  ) RETURN HTM_ID_RANGE_LIST IS
    vertices_cart HTM_VERTEX_LIST := HTM_VERTEX_LIST();
  BEGIN
    IF vertices_ra_dec IS NULL OR vertices_ra_dec.COUNT < 3 THEN
      RAISE_APPLICATION_ERROR(-20220, 'Convex hull requires at least 3 RA/Dec vertices.');
    END IF;
    IF query_level < 0 OR query_level > HTM_INDEX_CORE.g_max_query_level THEN
       RAISE_APPLICATION_ERROR(-20221, 'Query level is out of range.');
    END IF;

    vertices_cart.EXTEND(vertices_ra_dec.COUNT);
    FOR i IN 1 .. vertices_ra_dec.COUNT LOOP
      IF vertices_ra_dec(i).x IS NULL OR vertices_ra_dec(i).y IS NULL THEN
         RAISE_APPLICATION_ERROR(-20222, 'RA/Dec vertex components cannot be null.');
      END IF;
      vertices_cart(i) := HTM_VECTOR(vertices_ra_dec(i).x, vertices_ra_dec(i).y);
    END LOOP;
    RETURN convex_hull_intersect_cartesian(vertices_cart, query_level);
  END convex_hull_intersect;

  FUNCTION convex_hull_intersect_cartesian(
    vertices_cartesian HTM_VERTEX_LIST,
    query_level NUMBER
  ) RETURN HTM_ID_RANGE_LIST IS
    results HTM_ID_RANGE_LIST;
    params type_hull_params;
    root_nodes HTM_NUMBER_LIST := HTM_NUMBER_LIST(8,9,10,11,12,13,14,15);
    num_hull_vertices NUMBER;
    v_i HTM_VECTOR;
    v_i_plus_1 HTM_VECTOR;
    plane_normal HTM_VECTOR;
  BEGIN
    IF vertices_cartesian IS NULL OR vertices_cartesian.COUNT < 3 THEN
      RAISE_APPLICATION_ERROR(-20230, 'Convex hull requires at least 3 Cartesian vertices.');
    END IF;
     IF query_level < 0 OR query_level > HTM_INDEX_CORE.g_max_query_level THEN
       RAISE_APPLICATION_ERROR(-20231, 'Query level is out of range.');
    END IF;

    params.constraint_planes := HTM_VERTEX_LIST();
    num_hull_vertices := vertices_cartesian.COUNT;

    FOR i IN 1 .. num_hull_vertices LOOP
      v_i := vertices_cartesian(i);
      v_i.normalize(); 
      
      IF i = num_hull_vertices THEN
        v_i_plus_1 := vertices_cartesian(1);
      ELSE
        v_i_plus_1 := vertices_cartesian(i+1);
      END IF;
      v_i_plus_1.normalize(); 

      plane_normal := v_i.cross_product(v_i_plus_1);
      plane_normal.normalize();
      params.constraint_planes.EXTEND;
      params.constraint_planes(params.constraint_planes.LAST) := plane_normal;
    END LOOP;
    
    results := HTM_RANGE_UTILS.create_empty_range_list();

    FOR i IN 1 .. root_nodes.COUNT LOOP
      intersect_node_recursive(root_nodes(i), query_level, NULL, params, FALSE, results);
    END LOOP;

    HTM_RANGE_UTILS.merge_ranges(results); 
    RETURN results;
  END convex_hull_intersect_cartesian;

END HTM_QUERY_INTERFACE;
/
