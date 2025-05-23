CREATE OR REPLACE PACKAGE HTM_RANGE_UTILS AS

  -- Public Procedures and Functions

  FUNCTION create_empty_range_list RETURN HTM_ID_RANGE_LIST;

  PROCEDURE add_range(
    range_list IN OUT NOCOPY HTM_ID_RANGE_LIST,
    new_low_id NUMBER,
    new_high_id NUMBER
  );

  PROCEDURE merge_ranges(
    range_list IN OUT NOCOPY HTM_ID_RANGE_LIST
  );

  FUNCTION is_id_in_ranges(
    range_list HTM_ID_RANGE_LIST,
    id_to_check NUMBER
  ) RETURN BOOLEAN;

  FUNCTION range_list_to_string(
    range_list HTM_ID_RANGE_LIST
  ) RETURN VARCHAR2;
  
  FUNCTION get_range_count(
    range_list HTM_ID_RANGE_LIST
  ) RETURN NUMBER;

END HTM_RANGE_UTILS;
/
