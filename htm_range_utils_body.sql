CREATE OR REPLACE PACKAGE BODY HTM_RANGE_UTILS AS

  FUNCTION create_empty_range_list RETURN HTM_ID_RANGE_LIST IS
  BEGIN
    RETURN HTM_ID_RANGE_LIST();
  END create_empty_range_list;

  -- Private procedure to sort HTM_ID_RANGE_LIST by low_id, then high_id
  -- Using a simple bubble sort for demonstration.
  -- For large lists, more efficient sorting (e.g., merge sort, or using a global temporary table with ORDER BY) would be better.
  PROCEDURE sort_range_list(range_list IN OUT NOCOPY HTM_ID_RANGE_LIST) IS
    n PLS_INTEGER;
    temp_range HTM_ID_RANGE;
    swapped BOOLEAN;
  BEGIN
    IF range_list IS NULL OR range_list.COUNT < 2 THEN
      RETURN;
    END IF;

    n := range_list.COUNT;
    LOOP
      swapped := FALSE;
      FOR i IN 1 .. n - 1 LOOP
        IF (range_list(i).low_id > range_list(i+1).low_id) OR
           (range_list(i).low_id = range_list(i+1).low_id AND range_list(i).high_id > range_list(i+1).high_id)
        THEN
          temp_range := range_list(i);
          range_list(i) := range_list(i+1);
          range_list(i+1) := temp_range;
          swapped := TRUE;
        END IF;
      END LOOP;
      n := n - 1;
      EXIT WHEN NOT swapped;
    END LOOP;
  END sort_range_list;

  PROCEDURE merge_ranges(range_list IN OUT NOCOPY HTM_ID_RANGE_LIST) IS
    merged_list HTM_ID_RANGE_LIST;
    current_merged_range HTM_ID_RANGE;
  BEGIN
    IF range_list IS NULL OR range_list.COUNT < 2 THEN
      RETURN; -- Nothing to merge
    END IF;

    -- Sort the list first
    sort_range_list(range_list);

    merged_list := HTM_ID_RANGE_LIST();
    merged_list.EXTEND;
    merged_list(1) := range_list(1); -- Initialize with the first range

    FOR i IN 2 .. range_list.COUNT LOOP
      current_merged_range := merged_list(merged_list.LAST);
      IF range_list(i).low_id <= current_merged_range.high_id + 1 THEN
        -- Overlap or adjacent: merge
        current_merged_range.high_id := GREATEST(current_merged_range.high_id, range_list(i).high_id);
        merged_list(merged_list.LAST) := current_merged_range; -- Update the last element in merged_list
      ELSE
        -- Gap: add the new range as a separate element
        merged_list.EXTEND;
        merged_list(merged_list.LAST) := range_list(i);
      END IF;
    END LOOP;

    range_list := merged_list; -- Replace original list with merged one
  END merge_ranges;

  PROCEDURE add_range(
    range_list IN OUT NOCOPY HTM_ID_RANGE_LIST,
    new_low_id NUMBER,
    new_high_id NUMBER
  ) IS
    temp_low NUMBER := new_low_id;
    temp_high NUMBER := new_high_id;
  BEGIN
    IF temp_low IS NULL OR temp_high IS NULL THEN
        RAISE_APPLICATION_ERROR(-20101, 'New range IDs cannot be null.');
    END IF;

    IF temp_low > temp_high THEN
      -- Option 1: Raise an error
      RAISE_APPLICATION_ERROR(-20100, 'low_id cannot be greater than high_id.');
      -- Option 2: Swap them (uncomment to use)
      -- DECLARE swap_val NUMBER := temp_low;
      -- BEGIN temp_low := temp_high; temp_high := swap_val; END;
      -- Option 3: Ignore (do nothing, effectively what happens if error is not raised)
      -- RETURN; 
    END IF;
    
    IF range_list IS NULL THEN
      range_list := HTM_ID_RANGE_LIST();
    END IF;

    range_list.EXTEND;
    range_list(range_list.LAST) := HTM_ID_RANGE(temp_low, temp_high);
    
    -- Always merge after adding to maintain a minimal, sorted list
    merge_ranges(range_list);
  END add_range;

  FUNCTION is_id_in_ranges(
    range_list HTM_ID_RANGE_LIST,
    id_to_check NUMBER
  ) RETURN BOOLEAN IS
  BEGIN
    IF range_list IS NULL OR range_list.COUNT = 0 OR id_to_check IS NULL THEN
      RETURN FALSE;
    END IF;

    -- Assumes range_list is already merged and sorted (by add_range/merge_ranges)
    FOR i IN 1 .. range_list.COUNT LOOP
      IF id_to_check < range_list(i).low_id THEN
        RETURN FALSE; -- Sorted list, id is smaller than current range's low, so won't be in subsequent ranges
      END IF;
      IF id_to_check >= range_list(i).low_id AND id_to_check <= range_list(i).high_id THEN
        RETURN TRUE;
      END IF;
    END LOOP;
    RETURN FALSE;
  END is_id_in_ranges;

  FUNCTION range_list_to_string(
    range_list HTM_ID_RANGE_LIST
  ) RETURN VARCHAR2 IS
    str_repr VARCHAR2(32767) := '[';
  BEGIN
    IF range_list IS NULL OR range_list.COUNT = 0 THEN
      RETURN '[]';
    END IF;

    FOR i IN 1 .. range_list.COUNT LOOP
      IF i > 1 THEN
        str_repr := str_repr || ', ';
      END IF;
      str_repr := str_repr || '(' || TO_CHAR(range_list(i).low_id) || ',' || TO_CHAR(range_list(i).high_id) || ')';
    END LOOP;
    str_repr := str_repr || ']';
    RETURN str_repr;
  END range_list_to_string;
  
  FUNCTION get_range_count(
    range_list HTM_ID_RANGE_LIST
  ) RETURN NUMBER IS
  BEGIN
    IF range_list IS NULL THEN
      RETURN 0;
    END IF;
    RETURN range_list.COUNT;
  END get_range_count;

END HTM_RANGE_UTILS;
/
