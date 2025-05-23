CREATE OR REPLACE PACKAGE BODY HTM_SQL_API AS

  -- Initialization Procedure
  PROCEDURE initialize_htm_system(
    p_build_level NUMBER,
    p_query_level NUMBER
  ) IS
  BEGIN
    IF p_build_level IS NULL OR p_query_level IS NULL THEN
      RAISE_APPLICATION_ERROR(-20300, 'Build level and query level cannot be null.');
    END IF;
    IF p_build_level < 0 OR p_query_level < 0 THEN
      RAISE_APPLICATION_ERROR(-20301, 'Build level and query level must be non-negative.');
    END IF;
    -- Further validation might be needed if HTM_INDEX_CORE has stricter limits (e.g. max query_level)
    -- For now, assume HTM_INDEX_CORE handles its own internal validation of levels.
    HTM_INDEX_CORE.initialize_htm(p_build_level, p_query_level);
  END initialize_htm_system;

  -- Lookup Functions
  FUNCTION lookup_htm_id(
    p_ra NUMBER,
    p_dec NUMBER,
    p_target_level NUMBER
  ) RETURN NUMBER IS
    vec_p HTM_VECTOR;
  BEGIN
    IF p_ra IS NULL OR p_dec IS NULL OR p_target_level IS NULL THEN
      RAISE_APPLICATION_ERROR(-20310, 'RA, Dec, and target level cannot be null.');
    END IF;
    IF p_target_level < 0 OR p_target_level > HTM_INDEX_CORE.g_max_query_level THEN
        RAISE_APPLICATION_ERROR(-20311, 'Target level is out of range. Max query level is ' || HTM_INDEX_CORE.g_max_query_level);
    END IF;

    vec_p := HTM_VECTOR(p_ra, p_dec); -- Constructor handles conversion to Cartesian
    RETURN HTM_INDEX_CORE.id_by_point(vec_p, p_target_level);
  EXCEPTION
    WHEN OTHERS THEN
      -- Could log SQLERRM here
      RAISE; -- Re-raise the exception
  END lookup_htm_id;

  FUNCTION get_htm_point_radec(
    p_htm_id NUMBER
  ) RETURN VARCHAR2 IS
    cart_vec HTM_VECTOR;
    radec_vec HTM_VECTOR;
  BEGIN
    IF p_htm_id IS NULL THEN
      RAISE_APPLICATION_ERROR(-20320, 'HTM ID cannot be null.');
    END IF;

    cart_vec := HTM_INDEX_CORE.point_by_id(p_htm_id);
    IF cart_vec IS NULL THEN -- Should not happen if point_by_id is robust
        RAISE_APPLICATION_ERROR(-20321, 'Failed to get Cartesian point for HTM ID: ' || p_htm_id);
    END IF;
    
    radec_vec := HTM_GEOMETRY_UTILS.cartesian_to_ra_dec(cart_vec);
    IF radec_vec IS NULL OR radec_vec.x IS NULL OR radec_vec.y IS NULL THEN
        RAISE_APPLICATION_ERROR(-20322, 'Failed to convert Cartesian point to RA/Dec for HTM ID: ' || p_htm_id);
    END IF;

    RETURN TO_CHAR(radec_vec.x) || ',' || TO_CHAR(radec_vec.y);
  EXCEPTION
    WHEN OTHERS THEN
      RAISE;
  END get_htm_point_radec;

  FUNCTION get_htm_point_cartesian(
    p_htm_id NUMBER
  ) RETURN HTM_VECTOR IS
  BEGIN
    IF p_htm_id IS NULL THEN
      RAISE_APPLICATION_ERROR(-20330, 'HTM ID cannot be null.');
    END IF;
    RETURN HTM_INDEX_CORE.point_by_id(p_htm_id);
  EXCEPTION
    WHEN OTHERS THEN
      RAISE;
  END get_htm_point_cartesian;

  -- Intersection Query Functions (Table Functions)
  FUNCTION htm_circle_intersect(
    p_ra NUMBER,
    p_dec NUMBER,
    p_radius_degrees NUMBER,
    p_query_level NUMBER
  ) RETURN HTM_ID_RANGE_LIST PIPELINED IS
    result_ranges HTM_ID_RANGE_LIST;
  BEGIN
    -- Validation is handled by HTM_QUERY_INTERFACE.circle_region_intersect
    -- but can add specific checks here if desired (e.g. for nulls early)
    IF p_ra IS NULL OR p_dec IS NULL OR p_radius_degrees IS NULL OR p_query_level IS NULL THEN
      RAISE_APPLICATION_ERROR(-20340, 'Circle parameters (RA, Dec, Radius, Level) cannot be null.');
    END IF;
     IF p_query_level < 0 OR p_query_level > HTM_INDEX_CORE.g_max_query_level THEN
       RAISE_APPLICATION_ERROR(-20341, 'Query level is out of range.');
    END IF;


    result_ranges := HTM_QUERY_INTERFACE.circle_region_intersect(p_ra, p_dec, p_radius_degrees, p_query_level);

    IF result_ranges IS NOT NULL THEN
      FOR i IN 1 .. result_ranges.COUNT LOOP
        PIPE ROW (result_ranges(i));
      END LOOP;
    END IF;
    RETURN;
  EXCEPTION
    WHEN OTHERS THEN
      -- DBMS_OUTPUT.PUT_LINE('Error in htm_circle_intersect: ' || SQLERRM);
      RAISE;
  END htm_circle_intersect;

  FUNCTION htm_polygon_intersect(
    p_vertices_ra_dec_string VARCHAR2,
    p_query_level NUMBER,
    p_delimiter CHAR DEFAULT ';'
  ) RETURN HTM_ID_RANGE_LIST PIPELINED IS
    vertex_list HTM_VERTEX_LIST := HTM_VERTEX_LIST();
    ra_dec_pairs DBMS_SQL.VARCHAR2_TABLE; -- Using a PL/SQL table for split results
    current_pair_str VARCHAR2(100);
    ra_str VARCHAR2(50);
    dec_str VARCHAR2(50);
    ra_val NUMBER;
    dec_val NUMBER;
    pos_delimiter NUMBER;
    pos_comma NUMBER;
    
    temp_string VARCHAR2(32767) := p_vertices_ra_dec_string; -- Max length for varchar2 in PLSQL
    result_ranges HTM_ID_RANGE_LIST;

  BEGIN
    IF p_vertices_ra_dec_string IS NULL OR p_query_level IS NULL THEN
      RAISE_APPLICATION_ERROR(-20350, 'Polygon vertices string and query level cannot be null.');
    END IF;
    IF p_query_level < 0 OR p_query_level > HTM_INDEX_CORE.g_max_query_level THEN
       RAISE_APPLICATION_ERROR(-20351, 'Query level is out of range.');
    END IF;
    IF LENGTH(p_vertices_ra_dec_string) = 0 THEN
        RAISE_APPLICATION_ERROR(-20352, 'Polygon vertices string cannot be empty.');
    END IF;

    -- Basic split logic, can be enhanced with REGEXP_SUBSTR for more complex cases or different Oracle versions.
    LOOP
      pos_delimiter := INSTR(temp_string, p_delimiter);
      IF pos_delimiter > 0 THEN
        current_pair_str := TRIM(SUBSTR(temp_string, 1, pos_delimiter - 1));
        temp_string := TRIM(SUBSTR(temp_string, pos_delimiter + 1));
      ELSE
        current_pair_str := TRIM(temp_string);
        temp_string := NULL; -- No more delimiters
      END IF;
      
      IF LENGTH(current_pair_str) > 0 THEN
        pos_comma := INSTR(current_pair_str, ',');
        IF pos_comma IS NULL OR pos_comma = 0 OR pos_comma = LENGTH(current_pair_str) THEN
          RAISE_APPLICATION_ERROR(-20353, 'Invalid RA,Dec format in polygon string: "' || current_pair_str || '". Expected "RA,DEC".');
        END IF;
        ra_str := TRIM(SUBSTR(current_pair_str, 1, pos_comma - 1));
        dec_str := TRIM(SUBSTR(current_pair_str, pos_comma + 1));

        BEGIN
          ra_val := TO_NUMBER(ra_str);
          dec_val := TO_NUMBER(dec_str);
        EXCEPTION
          WHEN VALUE_ERROR THEN
            RAISE_APPLICATION_ERROR(-20354, 'Invalid number format for RA or Dec in polygon string: "' || current_pair_str || '".');
        END;
        
        -- Store RA as x, Dec as y for HTM_QUERY_INTERFACE.convex_hull_intersect
        vertex_list.EXTEND;
        vertex_list(vertex_list.LAST) := HTM_VECTOR(ra_val, dec_val, 0); -- z is not used by convex_hull_intersect for RA/Dec inputs
      END IF;

      EXIT WHEN temp_string IS NULL OR LENGTH(temp_string) = 0;
    END LOOP;
    
    IF vertex_list.COUNT < 3 THEN
      RAISE_APPLICATION_ERROR(-20355, 'Polygon requires at least 3 vertices. Parsed ' || vertex_list.COUNT || ' vertices.');
    END IF;

    result_ranges := HTM_QUERY_INTERFACE.convex_hull_intersect(vertex_list, p_query_level);

    IF result_ranges IS NOT NULL THEN
      FOR i IN 1 .. result_ranges.COUNT LOOP
        PIPE ROW (result_ranges(i));
      END LOOP;
    END IF;
    RETURN;
  EXCEPTION
    WHEN OTHERS THEN
      -- DBMS_OUTPUT.PUT_LINE('Error in htm_polygon_intersect: ' || SQLERRM);
      RAISE;
  END htm_polygon_intersect;

END HTM_SQL_API;
/
